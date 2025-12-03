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

  it "should normalize email to lowercase" do
    user.name = "Testing"
    user.email = "Steve@DOMAIN.com"
    user.save!
    user.email.should eq "steve@domain.com"
  end

  it "should hash passwords with bcrypt" do
    user.name = "Testing"
    user.email = "steve@domain.com"
    user.password = "my_secure_password"
    user.save!

    user.password_hash.should_not be_nil
    user.password_hash.should_not eq "my_secure_password"
    user.password_hash.try &.should start_with "$2a$"
  end

  it "should verify correct passwords" do
    user.name = "Testing"
    user.email = "steve@domain.com"
    user.password = "correct_password"
    user.save!

    user.verify_password("correct_password").should be_true
    user.verify_password("wrong_password").should be_false
  end

  it "should return false when verifying password without hash" do
    user.name = "Testing"
    user.email = "steve@domain.com"
    user.save!

    user.verify_password("any_password").should be_false
  end
end
