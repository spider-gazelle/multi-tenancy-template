require "../spec_helper"

describe App::Models::ApiKey do
  it "should create an API key for a user" do
    user = create_user
    api_key, raw_key = App::Models::ApiKey.create_for_user(user, "Test Key")

    api_key.persisted?.should be_true
    api_key.name.should eq "Test Key"
    api_key.user_id.should eq user.id
    raw_key.should start_with "sk_"
  end

  it "should hash the key and store prefix" do
    user = create_user
    api_key, raw_key = App::Models::ApiKey.create_for_user(user, "Test Key")

    api_key.key_hash.should_not eq raw_key
    api_key.key_prefix.should eq raw_key[0, 8]
  end

  it "should find API key by raw key" do
    user = create_user
    api_key, raw_key = App::Models::ApiKey.create_for_user(user, "Test Key")

    found = App::Models::ApiKey.find_by_key(raw_key)
    found.should_not be_nil
    found.not_nil!.id.should eq api_key.id
  end

  it "should return nil for invalid key" do
    App::Models::ApiKey.find_by_key("invalid_key").should be_nil
  end

  it "should authenticate valid key" do
    user = create_user
    api_key, raw_key = App::Models::ApiKey.create_for_user(user, "Test Key")

    authenticated = App::Models::ApiKey.authenticate(raw_key)
    authenticated.should_not be_nil
    authenticated.not_nil!.id.should eq api_key.id
  end

  it "should not authenticate expired key" do
    user = create_user
    api_key, raw_key = App::Models::ApiKey.create_for_user(
      user, "Test Key",
      expires_at: Time.utc - 1.hour
    )

    App::Models::ApiKey.authenticate(raw_key).should be_nil
  end

  it "should check scopes correctly" do
    user = create_user
    api_key, _ = App::Models::ApiKey.create_for_user(
      user, "Test Key",
      scopes: ["read", "write"]
    )

    api_key.has_scope?("read").should be_true
    api_key.has_scope?("write").should be_true
    api_key.has_scope?("delete").should be_false
  end

  it "should allow all scopes with wildcard" do
    user = create_user
    api_key, _ = App::Models::ApiKey.create_for_user(
      user, "Test Key",
      scopes: ["*"]
    )

    api_key.has_scope?("anything").should be_true
  end

  it "should allow all scopes when empty" do
    user = create_user
    api_key, _ = App::Models::ApiKey.create_for_user(user, "Test Key")

    api_key.has_scope?("anything").should be_true
  end

  it "should update last_used_at on authenticate" do
    user = create_user
    api_key, raw_key = App::Models::ApiKey.create_for_user(user, "Test Key")
    api_key.last_used_at.should be_nil

    App::Models::ApiKey.authenticate(raw_key)
    api_key.reload!
    api_key.last_used_at.should_not be_nil
  end
end
