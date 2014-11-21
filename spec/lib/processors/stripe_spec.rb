require 'spec_helper'

describe CatarseStripe::Processors::Stripe do
  context "process stripe details_for response" do
    let(:contribution) { Factory(:contribution, confirmed: false) }

    it "should create a new payment_notifications for contribution" do
      contribution.payment_notifications.should be_empty
      subject.process!(contribution, paypal_details_response)
      contribution.payment_notifications.should_not be_empty
    end

    it "should fill extra_data with all response data" do
      subject.process!(contribution, stripe_details_response)
      contribution.payment_notifications.first.extra_data.should == stripe_details_response
    end

    it "should confirm contribution when checkout status is completed" do
      subject.process!(contribution, stripe_details_response)
      contribution.confirmed.should be_true
    end

    it "should not confirm when checkout status is not completed" do
      subject.process!(contribution, stripe_details_response.merge!({"checkout_status" => "just_another_status"}) )
      contribution.confirmed.should be_false
    end
  end
end
