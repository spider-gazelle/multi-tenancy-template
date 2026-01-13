require "../spec_helper"

describe App::Health do
  client = AC::SpecHelper.client

  describe "GET /health" do
    it "returns ok status" do
      result = client.get("/health")
      result.status_code.should eq 200

      body = JSON.parse(result.body)
      body["status"].should eq "ok"
      body["timestamp"].should_not be_nil
    end
  end

  describe "GET /health/live" do
    it "returns ok status" do
      result = client.get("/health/live")
      result.status_code.should eq 200

      body = JSON.parse(result.body)
      body["status"].should eq "ok"
    end
  end

  describe "GET /health/ready" do
    it "checks database connectivity" do
      result = client.get("/health/ready")
      result.status_code.should eq 200

      body = JSON.parse(result.body)
      body["status"].should eq "ok"
      body["checks"]["database"].should eq "ok"
    end
  end
end
