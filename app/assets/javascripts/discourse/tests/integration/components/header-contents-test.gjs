import { getOwner } from "@ember/owner";
import { render } from "@ember/test-helpers";
import { module, test } from "qunit";
import sinon from "sinon";
import Contents from "discourse/components/header/contents";
import { setupRenderingTest } from "discourse/tests/helpers/component-test";

module("Integration | Component | Header | Contents", function (hooks) {
  setupRenderingTest(hooks);

  test("showHeaderSearch", async function (assert) {
    const site = getOwner(this).lookup("service:site");
    const toggleNavigationMenu = () => {};

    sinon.stub(site, "mobileView").value(true);

    await render(
      <template>
        <Contents
          @sidebarEnabled={{true}}
          @toggleNavigationMenu={{toggleNavigationMenu}}
          @showSidebar={{true}}
        >test</Contents>
      </template>
    );

    assert
      .dom(".floating-search-input-wrapper")
      .doesNotExist("it does not display when the site is in mobile view");
  });
});
