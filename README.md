## The stripe_controller is a work in progress and things will be changing very rapidly. BEWARE!
### Tests are non-functional at this point and will be adjusted to Stripe soon!

# CatarseStripe v. 0.1.0.0.1 - Feb 2013

Catarse Stripe integration with [Catarse](http://github.com/danielweinmann/catarse) crowdfunding platform. 

So far, catarse_stripe uses Omniauth for an auth connection and to use Catarse as a Platform app. See the wiki on how to use Stripe-Connect.

## Installation

Add this lines to your Catarse application's Gemfile under the payments section:

    gem 'catarse_stripe', :git => 'git://github.com/lvxn0va/catarse_stripe.git'
    gem 'stripe', :git => 'https://github.com/stripe/stripe-ruby'

And then execute:

    $ bundle

Install the database migrations

    bundle exec rake catarse_stripe:install:migrations
    bundle exec rake db:migrate
    
## Usage

Configure the routes for your Catarse application. Add the following lines in the routes file (config/routes.rb):

    mount CatarseStripe::Engine => "/", :as => "catarse_stripe"

### CatarseSettingss  

Signup for an account at [STRIPE PAYMENTS](http://www.stripe.com) - Go into your account settings and get your API Keys - Be sure to use your 'Test' keys until you're ready to go live. Alos make sure the live/test toggle in the Dashboard is appropriately set.  

You'll also need to register your application with Stripe to allow you to create new Project owners and collect an app fee from them as a Catarse Platform owner. In Account Settings, go to Applications and fill out the info. When approved, add your ":stripe_client_id" to configurations as below.  

Create this configurations into Catarse database:

    stripe_api_key, stripe_secret_key and stripe_test (boolean)

In Rails console, run this:

    CatarseSettings.create!(name: "stripe_api_key", value: "API_KEY")
    CatarseSettings.create!(name: "stripe_secret_key", value: "SECRET_KEY")
    CatarseSettings.create!(name: "stripe_test", value: "TRUE/FALSE")
    
If you've already created your application and been approved at Stripe.com add your Client_id  

    CatarseSettings.create!(name: "stripe_client_id", value: "STRIPE_CLIENT_ID")  

NOTE: Be sure to add the correct keys from the API section of your Stripe account settings. Stripe_Test: TRUE = Using Stripe Test Server/Sandbox Mode / FALSE = Using Stripe live server.  

### Authorization

Users who will be creating projects can now create and connect a Stripe.com project payments account. This is the account that will receive funds for each project. At this beta stage you will need to make some changes to your catarse app manually to get the buttons and links setup.  

TODO= Add auto insertion for following code to catarse_stripe rake tasks and engine install.  

Just above the "#password" field and in the "My_Data" section, add the following in:  
    
    #app/views/users/_current_user_fields.html.slim
    ...
    #payment_gateways
    h1= t('.payment_gateways')
    ul
      li
        - if @user.stripe_key.blank?
          = link_to( image_tag('catarse_stripe/auth/stripe_blue.png'), '/payment/stripe/auth')
        - else
          = image_tag 'catarse_stripe/auth/stripe-solid.png'
          br
          p= t('.stripe_key_info')
          p= @user.stripe_key
          br
          p= t('.stripe_customer_info')
          p= @user.stripe_userid
          ...

This will create a button in the User/settings tab to connect to the catarse_stripe auth and get a UserID, Secretkey and PublicKey for the User/Project Owner. 

ADDITIONALLY, you can allow your users to create a new user account and signin via Omniauth. This would take care of two things:  

1) New User would have a new Catarse account, as an alternative to linking their Google/Twitter/Facebook accounts.  
2) This user connected with Stripe will also be ready to create projects and accept payments without having to connect to Stripe in the User#Settings section.  

Setting up Omniauth for Stripe is exactly like setting up other providers. Add provider :stripe_connect into omniauth.rb after "facebook":  
    
    #/app/config/initializers/omniauth.rb

    ....
    
    Rails.application.config.middleware.use OmniAuth::Builder do  
      use OmniAuth::Strategies::OpenID, :store => OpenID::Store::Filesystem.new("#{Rails.root}/tmp")

      provider :open_id, :name => 'google', :identifier => 'https://www.google.com/accounts/o8/id'
      provider :open_id, :name => 'yahoo', :identifier => 'yahoo.com'
      provider :facebook, ENV['FACEBOOK_APP_ID'], ENV['FACEBOOK_APP_SECRET'], {:client_options => {:ssl => {:ca_path => "/etc/ssl/certs"}}, :scope => 'publish_stream,email'}
      provider :stripe_connect, CatarseSettings['stripe_client_id'], CatarseSettings['stripe_secret_key'], {:scope => 'read_write', :stripe_landing => 'register'}
    
    ...  

And copy your User's new keys to the appropriate columns in the database. After the "facebook" section:  
    
    ...

    def self.create_with_omniauth(auth)
        ...

        if auth["provider"] == "facebook"
          user.image_url = "https://graph.facebook.com/#{auth['uid']}/picture?type=large"
        end
        
        #New Stripe User keys to database
        if auth["provider"] == "stripe_connect"
          user.stripe_key = auth["info"]["stripe_publishable_key"]
          user.stripe_userid = auth["uid"]
          user.stripe_access_token = auth["credentials"]["token"]
        end

      ...
    end  

Now that you've created your auth points, you'll then need to copy those keys to the matching columns in the projects table.  You can do this automatically when a created project is loaded by adding this to the bottom of the projects controller code:  
    
    #app/controllers/projects_controller.rb
    ...
    def check_for_stripe_keys
      if @project.stripe_userid.nil?
        [:stripe_access_token, :stripe_key, :stripe_userid].each do |field|
          @project.send("#{field.to_s}=", @project.user.send(field).dup)
        end
      elsif @project.stripe_userid != @project.user.stripe_userid
        [:stripe_access_token, :stripe_key, :stripe_userid].each do |field|
          @project.send("#{field.to_s}=", @project.user.send(field).dup)
        end
      end
      @project.save
    end  
    ...

The insert `check_for_stripe_keys` in the :show method above the 'show!' entry like so:
    
    ...
    check_for_stripe_keys

      show!{
        @title = @project.name
        @rewards = @project.rewards.order(:minimum_value).all
        @contributions = @project.contributions.confirmed.limit(12).order("confirmed_at DESC").all
        fb_admins_add(@project.user.facebook_id) if @project.user.facebook_id
        @update = @project.updates.where(:id => params[:update_id]).first if params[:update_id].present?
      }
     ...

As well as in the :create method after the "bitly" section like so:  
    
    ...
    unless @project.new_record?
      @project.reload
      @project.update_attributes({ short_url: bitly })
    end
    check_for_stripe_keys
    ...

## Development environment setup

Clone the repository:

    $ git clone git://github.com/lvxn0va/catarse_stripe.git

Add the catarse code into test/dummy:

    $ git submodule init
    $ git submodule update

And then execute:

    $ bundle

## Troubleshooting in development environment

Remove the admin folder from test/dummy application to prevent a weird active admin bug:

    $ rm -rf test/dummy/app/admin

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request


This project rocks and uses MIT-LICENSE.
