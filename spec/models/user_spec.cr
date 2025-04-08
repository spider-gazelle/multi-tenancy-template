require "../spec_helper"

describe App::Models::User do
  user = App::Models::User.new

  Spec.around_each do |test|
    user = App::Models::User.new
    test.run
    user.destroy
  end

  it "should be able to create a user" do
    user.name = "Testing"
    user.email = "steve@domain.com"
    user.save!
  end
end
