require 'catarse_stripe/processors'
require 'json'
require 'stripe'
require 'oauth2'

module CatarseStripe::Payment
    class StripeController < ApplicationController
    
    skip_before_filter :verify_authenticity_token, :only => [:notifications]
    skip_before_filter :detect_locale, :only => [:notifications, :connect]
    skip_before_filter :set_locale, :only => [:notifications, :connect]
    skip_before_filter :force_http

    before_filter :setup_auth_gateway

    SCOPE = "projects.backers.checkout"
    AUTH_SCOPE = "users.auth"

    layout :false

    #Makes the call to @client.auth_code.authorize_url from auth.html.erg
    def auth
      @stripe_user = current_user
      respond_to do |format|
        format.html
        format.js
      end
    end

    #Brings back the authcode from Stripe and makes another call to Stripe to convert to a authtoken
    def callback
      @stripe_user = current_user
      code = params[:code]

      # @response = @client.auth_code.get_token(code, {
      # :headers => {'Authorization' => "#{::Configuration['stripe_secret_key']}"} #Platform Secret Key
      # })
      
      @response = @client.auth_code.get_token(code, :client_secret=>::Configuration['stripe_secret_key'], :params => {:scope => 'read_write'})
      
      #Save PROJECT owner's new keys
      @stripe_user.stripe_access_token = @response.token
      @stripe_user.stripe_key = @response.params['stripe_publishable_key']
      @stripe_user.stripe_userid = @response.params['stripe_user_id']
      @stripe_user.save

      
      return redirect_to payment_stripe_auth_path
    rescue Stripe::AuthenticationError => e
      ::Airbrake.notify({ :error_class => "Stripe #Pay Error", :error_message => "Stripe #Pay Error: #{e.inspect}", :parameters => params}) rescue nil
      Rails.logger.info "-----> #{e.inspect}"
      flash[:error] = e.message
      return redirect_to main_app.user_path(@stripe_user)
    end

    def review
    
    end

    def ipn
      backer = Backer.where(:payment_id => details.id).first
      if backer
        notification = backer.payment_notifications.new({
          extra_data: JSON.parse(params.to_json.force_encoding(params['charset']).encode('utf-8'))
        })
        notification.save!
        backer.update_attribute :payment_service_fee => details.fee
      end
      return render status: 200, nothing: true
    rescue Stripe::CardError => e
      ::Airbrake.notify({ :error_class => "Stripe Notification Error", :error_message => "Stripe Notification Error: #{e.inspect}", :parameters => params}) rescue nil
      return render status: 200, nothing: true
    end

    def notifications
      backer = Backer.find params[:id]
      details = Stripe::Charge.retrieve(
          id: backer.payment_id
          )
      if details.paid = true
        build_notification(backer, details)
        render status: 200, nothing: true
      else
        render status: 404, nothing: true
      end
    rescue Stripe::CardError => e
      ::Airbrake.notify({ :error_class => "Stripe Notification Error", :error_message => "Stripe Notification Error: #{e.inspect}", :parameters => params}) rescue nil
      render status: 404, nothing: true
    end
    
    def charge
      @backer = current_user.backs.find params[:id]
      #access_token = @backer.project.stripe_access_token #Project Owner SECRET KEY

      respond_to do |format|
        format.html
        format.js
      end
    end 

    def pay_auth
      @backer = current_user.backs.find params[:id]
      access_token = ::Configuration[:stripe_secret_key] #@backer.project.stripe_access_token #Project Owner SECRET KEY
      begin
        customer = Stripe::Customer.create(
          {
           email: @backer.payer_email,
           card: params[:stripeToken]
           },
           access_token
        )
        @backer.update_attributes(:payment_token => customer.id, :payment_token_card => customer.default_card )
        @backer.save
        flash[:notice] = "Stripe Customer ID Saved!"
        
              
        redirect_to payment_success_stripe_url(id: @backer.id)
      rescue Stripe::CardError => e
        ::Airbrake.notify({ :error_class => "Stripe #Pay Error", :error_message => "Stripe #Pay Error: #{e.inspect}", :parameters => params}) rescue nil
        Rails.logger.info "-----> #{e.inspect}"
        flash[:error] = e.message
        return redirect_to main_app.new_project_backer_path(@backer.project)
      end
    end
    
    def self.testing(event)
      binding.pry
      
    end
    
    def self.capture(backer)
      
      @backer = backer
      access_token = @backer.project.stripe_access_token #Project Owner SECRET KEY
      
      begin

        #binding.pry

        user_token = Stripe::Token.create(
          {:customer => @backer.payment_token, :card => @backer.payment_token_card},
          access_token # user's access token from the Stripe Connect flow
        )
        
        #binding.pry
        
        response = Stripe::Charge.create(
          {
          amount: @backer.price_in_cents,
          card: user_token.id,
          currency: 'usd',
          description: 'test',
          application_fee: @backer.catarse_fee_in_cents
          },
          access_token
        )

        @backer.update_attributes({
          :payment_method => 'Stripe',
          #:payment_token => response.customer, #Stripe Backer Customer_id
          :payment_id => response.id, #Stripe Backer Payment Id
          #:confirmed => response.paid #Paid = True, Confirmed =  true
        })
        @backer.save

        self.build_notification(@backer, response) # this is where we set it to confirm.

      rescue Stripe::CardError => e
        ::Airbrake.notify({ :error_class => "Stripe #Pay Error", :error_message => "Stripe #Pay Error: #{e.inspect}", :parameters => params}) rescue nil
        Rails.logger.info "-----> #{e.inspect}"

      end
      
    end

    def success
      backer = current_user.backs.find params[:id]
      access_token = backer.project.stripe_access_token #Project Owner SECRET KEY
      begin
        # details = Stripe::Charge.retrieve(
        # {
        #   id: backer.payment_id
        #   },
        #   access_token
        #   )
        #
        # build_notification(backer, details)
        #
        # if details.id
        #   backer.update_attribute :payment_id, details.id
        # end
        backer.authorized!
        stripe_flash_success
        redirect_to main_app.project_backer_path(project_id: backer.project.id, id: backer.id)
      rescue Stripe::CardError => e
        ::Airbrake.notify({ :error_class => "Stripe Error", :error_message => "Stripe Error: #{e.message}", :parameters => params}) rescue nil
        Rails.logger.info "-----> #{e.inspect}"
        flash[:error] = e.message
        return redirect_to main_app.new_project_backer_path(backer.project)
      end
    end

    def cancel
      backer = current_user.backs.find params[:id]
      flash[:failure] = t('stripe_cancel', scope: SCOPE)
      redirect_to main_app.new_project_backer_path(backer.project)
    end

  private
    #Setup the Oauth2 Stripe call with needed params - See initializers.stripe..rb..the Stripe keys are setup in the seed.db or added manually with a Configuration.create! call.
    def setup_auth_gateway
      session[:oauth] ||= {}

      @client = OAuth2::Client.new((::Configuration['stripe_client_id']), (::Configuration['stripe_api_key']), {
        :site => 'https://connect.stripe.com',
        :authorize_url => '/oauth/authorize',
        :token_url => '/oauth/token'
      })
    end

    def self.build_notification(backer, data)
      processor = CatarseStripe::Processors::Stripe.new
      processor.process!(backer, data)
    end

    def stripe_flash_error
      flash[:failure] = t('stripe_error', scope: SCOPE)
    end

    def stripe_flash_success
      flash[:success] = t('success', scope: SCOPE)
    end

    def stripe_auth_flash_error
      flash[:failure] = t('stripe_error', scope: AUTH_SCOPE)
    end

    def stripe_auth_flash_success
      flash[:success] = t('success', scope: AUTH_SCOPE)
    end
  end
end