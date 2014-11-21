# PaymentEngines.register({name: 'stripe', review_path: ->(contribution){ CatarseStripe::Engine.routes.url_helpers.payment_review_stripe_path(contribution) }, locale: 'en'})

begin
  PaymentEngines.register(CatarseStripe::PaymentEngine.new)
rescue Exception => e
  puts "Error while registering payment engine: #{e}"
end