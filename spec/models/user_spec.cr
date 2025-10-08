require "../spec_helper"

describe App::Models::User do
  user = App::Models::User.new

  Spec.before_each do
    user.destroy rescue nil
    user = App::Models::User.new
  end

  it "should be able to create a user" do
    user.name = "Testing"
    user.email = "steve@domain.com"
    user.save!
  end
end
