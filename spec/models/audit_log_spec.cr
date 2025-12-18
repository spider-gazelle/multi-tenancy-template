require "../spec_helper"

describe App::Models::AuditLog do
  it "should create an audit log entry" do
    log = App::Models::AuditLog.log(
      action: App::Models::AuditLog::Actions::CREATE,
      resource_type: App::Models::AuditLog::Resources::USER
    )

    log.persisted?.should be_true
    log.action.should eq "create"
    log.resource_type.should eq "user"
  end

  it "should log with user context" do
    user = create_user
    log = App::Models::AuditLog.log(
      action: App::Models::AuditLog::Actions::LOGIN,
      resource_type: App::Models::AuditLog::Resources::USER,
      user: user
    )

    log.user_id.should eq user.id
  end

  it "should log with organization context" do
    org = create_organization
    log = App::Models::AuditLog.log(
      action: App::Models::AuditLog::Actions::UPDATE,
      resource_type: App::Models::AuditLog::Resources::ORGANIZATION,
      organization: org
    )

    log.organization_id.should eq org.id
  end

  it "should log with resource_id" do
    user = create_user
    log = App::Models::AuditLog.log(
      action: App::Models::AuditLog::Actions::DELETE,
      resource_type: App::Models::AuditLog::Resources::USER,
      resource_id: user.id
    )

    log.resource_id.should eq user.id
  end

  it "should log with details" do
    log = App::Models::AuditLog.log(
      action: App::Models::AuditLog::Actions::UPDATE,
      resource_type: App::Models::AuditLog::Resources::ORGANIZATION,
      details: {"field" => "name", "old_value" => "Old", "new_value" => "New"}
    )

    log.details.should_not be_nil
  end

  it "should log with IP and user agent" do
    log = App::Models::AuditLog.log(
      action: App::Models::AuditLog::Actions::LOGIN,
      resource_type: App::Models::AuditLog::Resources::USER,
      ip_address: "192.168.1.1",
      user_agent: "Mozilla/5.0"
    )

    log.ip_address.should eq "192.168.1.1"
    log.user_agent.should eq "Mozilla/5.0"
  end

  it "should have timestamps" do
    log = App::Models::AuditLog.log(
      action: App::Models::AuditLog::Actions::CREATE,
      resource_type: App::Models::AuditLog::Resources::GROUP
    )

    log.created_at.should_not be_nil
  end
end
