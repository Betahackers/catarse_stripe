require 'stripe'
require 'stripe_event'

#Main Platform Stripe Keys - Enter manually according to catarse_stripe README or add to seeds.db - 
#As it stands, because of Stripe Connect, the only key being referred to here is the Main Platform App key 'stripe_client_id' in Omniauth.rb
Rails.configuration.stripe = {
  :publishable_key => (::CatarseSettings.get_without_cache('stripe_api_key')),
  :secret_key      => (::CatarseSettings.get_without_cache('stripe_secret_key')),
  :stripe_client_id => (::CatarseSettings.get_without_cache('stripe_client_id'))
}

Stripe.api_key = Rails.configuration.stripe[:secret_key]
STRIPE_PUBLIC_KEY = Rails.configuration.stripe[:publishable_key]
STRIPE_CLIENT_ID = Rails.configuration.stripe[:stripe_client_id]

StripeEvent.configure do |events|
  events.subscribe 'charge.succeeded' do |event|
    # # Define subscriber behavior based on the event object
    # event.class       #=> Stripe::Event
    # event.type        #=> "charge.failed"
    # event.data.object #=> #<Stripe::Charge:0x3fcb34c115f8>
    # binding.pry
    b = Contribution.find_by_payment_id(event.data.object.id)
    b.confirm!
  end
  
  events.subscribe 'charge.failed' do |event|
    b = Contribution.find_by_payment_id(event.data.object.id)
    b.decline!
  end

  events.all do |event|
    #binding.pry
  end
end

StripeEvent.event_retriever = lambda do |params|
  if params[:user_id]
    api_key = User.find_by!(stripe_userid: params[:user_id]).stripe_access_token
    #binding.pry if params['type'] != "application_fee.created"
    Stripe::Event.retrieve(params[:id], api_key)
  else
    Stripe::Event.retrieve(params[:id])
  end
end
  


#Stripe.api_key = ENV['STRIPE_API_KEY'] #PROJECT secret
#STRIPE_PUBLIC_KEY = ENV['STRIPE_PUBLIC_KEY'] #PROJECT publishable
#STRIPE_CLIENT_ID = ENV['STRIPE_CLIENT_ID'] #Platform owner app key