require "../spec_helper"

describe App::Models::Organization do
  org = App::Models::Organization.new

  Spec.before_each do
    org = App::Models::Organization.new
  end

  it "should be able to create an organization" do
    org.name = "Testing"
    org.save!

    org2 = App::Models::Organization.find!(org.id)
    org2.name.should eq "Testing"
    org2.created_at.should_not be_nil
    org2.updated_at.should_not be_nil

    org.destroy
    expect_raises(PgORM::Error::RecordNotFound) { org2.reload! }
  end

  it "should manage organisation owners" do
    user = App::Models::User.new
    user.name = "It's Steve"
    user.email = "steve@org.com"
    user.save!

    org.name = "Testing"
    org.owner = user
    org.save!

    org2 = App::Models::Organization.find!(org.id)
    org2.owner_id.should eq user.id

    user.destroy

    org2 = App::Models::Organization.find!(org.id)
    org2.owner_id.should be_nil
  end
end
