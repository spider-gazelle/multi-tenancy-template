require "../spec_helper"

module App::Models
  describe OrganizationUser do
    org : Organization? = nil
    user : User? = nil

    Spec.before_each do
      org.try(&.destroy) rescue nil
      user.try(&.destroy) rescue nil
      org = Organization.new(name: "Testing")
      org.not_nil!.save!
      user = User.new(name: "Testing", email: "steve@orguser.com")
      user.not_nil!.save!
    end

    it "should be able to associate a user with an organisation" do
      o = org.not_nil!
      u = user.not_nil!
      o.add u
      o.users.to_a.map(&.id).first?.should eq u.id
      u.organizations.first.id.should eq o.id
    end

    it "should be able to associate multiple users with an organisation" do
      o = org.not_nil!
      u = user.not_nil!
      user2 = User.new(name: "User2", email: "user2@org.com")
      user2.save!
      user3 = User.new(name: "User3", email: "user3@org.com")
      user3.save!

      o.add u
      o.add user2

      o.users.map(&.id).to_set.should eq [u.id, user2.id].to_set
      user3.organizations.to_a.should be_empty

      user2.destroy
      user3.destroy
      # we've left the original user
      OrganizationUser.all.count.should eq 1
    end

    it "should be able to associate multiple organisations with a user" do
      o = org.not_nil!
      u = user.not_nil!
      org2 = Organization.new(name: "org2")
      org2.save!
      org3 = Organization.new(name: "org3")
      org3.save!

      o.add u
      org2.add u

      u.organizations.map(&.id).to_set.should eq [o.id, org2.id].to_set
      org3.users.to_a.should be_empty

      org2.destroy
      org3.destroy
      # we've left the original org
      OrganizationUser.all.count.should eq 1
    end

    it "use helper functions to manage users" do
      o = org.not_nil!
      u = user.not_nil!
      user2 = User.new(name: "User2", email: "user2@org.com")
      user2.save!
      user3 = User.new(name: "User3", email: "user3@org.com")
      user3.save!

      o.add u
      o.add user2
      o.add user3
      o.users.map(&.id).to_set.should eq [u.id, user2.id, user3.id].to_set

      o.remove u
      o.remove user2
      o.users.count.should eq 1
      o.remove user3
      o.users.count.should eq 0
      OrganizationUser.all.count.should eq 0

      user2.destroy
      user3.destroy
    end
  end
end
