require "../spec_helper"

describe App::Models::Organization do
  it "should be able to create an organization" do
    org = App::Models::Organization.new
    org.name = "Testing"
    org.save!

    org2 = App::Models::Organization.find!(org.id)
    org2.name.should eq "Testing"
    org2.created_at.should_not be_nil
    org2.updated_at.should_not be_nil

    org.destroy
    expect_raises(PgORM::Error::RecordNotFound) { org2.reload! }
  end
end
