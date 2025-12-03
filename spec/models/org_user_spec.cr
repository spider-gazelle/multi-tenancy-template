require "../spec_helper"

module App::Models
  describe OrganizationUser do
    Spec.before_each do
      Organization.clear
      User.clear
      OrganizationUser.clear
    end

    it "should be able to associate a user with an organisation" do
      org = Organization.new(name: "Testing")
      org.save!
      user = User.new(name: "Testing", email: "steve@orguser.com")
      user.save!

      org.add user
      org.users.to_a.map(&.id).first?.should eq user.id
      user.organizations.first.id.should eq org.id
    end

    it "should be able to associate multiple users with an organisation" do
      org = Organization.new(name: "Testing")
      org.save!
      user = User.new(name: "Testing", email: "steve@orguser.com")
      user.save!
      user2 = User.new(name: "User2", email: "user2@org.com")
      user2.save!
      user3 = User.new(name: "User3", email: "user3@org.com")
      user3.save!

      org.add user
      org.add user2

      org.users.map(&.id).to_set.should eq [user.id, user2.id].to_set
      user3.organizations.to_a.should be_empty

      user2.destroy
      user3.destroy
      # we've left the original user
      OrganizationUser.all.count.should eq 1
    end

    it "should be able to associate multiple organisations with a user" do
      org = Organization.new(name: "Testing")
      org.save!
      user = User.new(name: "Testing", email: "steve@orguser.com")
      user.save!
      org2 = Organization.new(name: "org2")
      org2.save!
      org3 = Organization.new(name: "org3")
      org3.save!

      org.add user
      org2.add user

      user.organizations.map(&.id).to_set.should eq [org.id, org2.id].to_set
      org3.users.to_a.should be_empty

      org2.destroy
      org3.destroy
      # we've left the original org
      OrganizationUser.all.count.should eq 1
    end

    it "use helper functions to manage users" do
      org = Organization.new(name: "Testing")
      org.save!
      user = User.new(name: "Testing", email: "steve@orguser.com")
      user.save!
      user2 = User.new(name: "User2", email: "user2@org.com")
      user2.save!
      user3 = User.new(name: "User3", email: "user3@org.com")
      user3.save!

      org.add user
      org.add user2
      org.add user3
      org.users.map(&.id).to_set.should eq [user.id, user2.id, user3.id].to_set

      org.remove user
      org.remove user2
      org.users.count.should eq 1
      org.remove user3
      org.users.count.should eq 0
      OrganizationUser.all.count.should eq 0

      user2.destroy
      user3.destroy
    end
  end
end
