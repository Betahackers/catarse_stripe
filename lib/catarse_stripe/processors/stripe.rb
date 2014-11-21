module CatarseStripe
  module Processors
    class Stripe

      def process!(contribution, data)
        
        
        status = data["captured"]
        
        puts 'jasonjasonjason'
        puts data
        puts '------'
        puts status
        puts '---'

        notification = contribution.payment_notifications.new({
          extra_data: data
        })

        notification.save!

        contribution.waiting! if captured?(status)
      rescue Exception => e
        ::Airbrake.notify({ :error_class => "Stripe Processor Error", :error_message => "Stripe Processor Error: #{e.inspect}", :parameters => data}) rescue nil
      end

      protected

      def captured?(status)
        status == true
      end

    end
  end
end