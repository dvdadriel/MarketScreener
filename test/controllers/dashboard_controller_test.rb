require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  test "renders with crypto disabled (default): no crypto tab, stock shown" do
    get root_path
    assert_response :success
    assert_select "[data-tab-name=stock]"
    assert_select "[data-tab-name=crypto]", false, "crypto tab must be hidden when CRYPTO_ENABLED is false"
  end
end
