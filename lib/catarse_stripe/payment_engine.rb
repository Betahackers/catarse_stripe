begin
  module CatarseStripe
    class PaymentEngine# < PaymentEngines::Interface

      def name
        'stripe'
      end

      def review_path contribution
        CatarseStripe::Engine.routes.url_helpers.payment_review_stripe_path(contribution)
      end

      def locale
        'en'
      end

    end
  end
rescue Exception => e
  puts "Error while use payment engine interface: #{e}"
end