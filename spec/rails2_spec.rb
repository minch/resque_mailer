require File.join(File.expand_path(File.dirname(__FILE__)), 'spec_helper')

gem     'actionmailer', '~>2.3.4'
require 'action_mailer'
require 'resque_mailer/rails2'
#require 'active_record'

ActionMailer::Base.delivery_method = :test

class Rails2Mailer < ActionMailer::Base
  include Resque::Mailer
  MAIL_PARAMS = { :to => "misio@example.org" }

  def test_mail(opts={})
    @subject    = 'subject'
    @body       = 'mail body'
    @recipients = opts[:to]
    @from       = 'from@example.org'
    @sent_on    = Time.now
    @headers    = {}
  end
end

class User # < ActiveRecord::Base
  attr_accessor :id
end

describe Rails2Mailer do
  before do
    Rails2Mailer.stub(:current_env => :test)
  end

  describe '#deliver' do
    before(:all) do
      @delivery = lambda {
        Rails2Mailer.deliver_test_mail(Rails2Mailer::MAIL_PARAMS)
      }
    end

    before(:each) do
      Resque.stub(:enqueue)
    end

    it 'should not deliver the email synchronously' do
      lambda { @delivery.call }.should_not change(ActionMailer::Base.deliveries, :size)
    end

    it 'should place the deliver action on the Resque "mailer" queue' do
      Resque.should_receive(:enqueue).with(Rails2Mailer, "deliver_test_mail!", Rails2Mailer::MAIL_PARAMS)
      @delivery.call
    end

    context "when *args contains models" do
      let(:user) { user = User.new ; user.id = 1971 ; user }
      let(:mail_params) do
        mail_params = Rails2Mailer::MAIL_PARAMS
        mail_params.store(:user, user)
        mail_params
      end

      it "should send objects with model hashes" do
        expected = {:user=>{:model=>"User", :id=>1971}}

        @delivery = lambda { Rails2Mailer.deliver_test_mail(mail_params) }
        Resque.should_receive(:enqueue).with(Rails2Mailer, "deliver_test_mail!", expected)

        @delivery.call
      end

      it "should receive objects with model hashes" do
        # Hash will come from resque as json so all keys will be strings
        args = { "user" => {"model" => "User", "id" => 1971} }
        expected = { "user" => user }

        User.stub(:find).and_return(user)

        Rails2Mailer.send(:objects_from_model_hashes, args).should == expected
      end
    end

    context "when current env is excluded" do
      it 'should not deliver through Resque for excluded environments' do
        Resque::Mailer.stub(:excluded_environments => [:custom])
        Rails2Mailer.should_receive(:current_env).and_return(:custom)
        Resque.should_not_receive(:enqueue)
        @delivery.call
      end
    end
  end

  describe '#deliver!' do
    it 'should deliver the email synchronously' do
      lambda { Rails2Mailer.deliver_test_mail!(Rails2Mailer::MAIL_PARAMS) }.should change(ActionMailer::Base.deliveries, :size).by(1)
    end
  end

  describe ".perform" do
    it 'should perform a queued mailer job' do
      lambda {
        Rails2Mailer.perform("deliver_test_mail!", Rails2Mailer::MAIL_PARAMS)
      }.should change(ActionMailer::Base.deliveries, :size).by(1)
    end
  end
end
