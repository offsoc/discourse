import DiscourseRoute from "discourse/routes/discourse";
import { i18n } from "discourse-i18n";

export default class AdminConfigThemesAndComponentsThemesRoute extends DiscourseRoute {
  async model() {
    const themes = await this.store.findAll("theme");
    return themes.reject((t) => t.component);
  }

  titleToken() {
    return i18n("admin.config_areas.themes_and_components.themes.title");
  }
}
