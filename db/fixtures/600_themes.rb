# frozen_string_literal: true

theme_exists = Theme.exists?

SystemThemesManager.sync!

# we can not guess what to do if customization already started, so skip it
if !theme_exists
  STDERR.puts "> Seeding theme and color schemes"

  color_schemes = [
    { name: I18n.t("color_schemes.dark"), base_scheme_id: "Dark" },
    { name: I18n.t("color_schemes.wcag"), base_scheme_id: "WCAG" },
    { name: I18n.t("color_schemes.wcag_dark"), base_scheme_id: "WCAG Dark" },
    { name: I18n.t("color_schemes.dracula"), base_scheme_id: "Dracula" },
    { name: I18n.t("color_schemes.solarized_light"), base_scheme_id: "Solarized Light" },
    { name: I18n.t("color_schemes.solarized_dark"), base_scheme_id: "Solarized Dark" },
  ]

  color_schemes.each do |cs|
    scheme = ColorScheme.find_by(base_scheme_id: cs[:base_scheme_id])
    scheme ||=
      ColorScheme.create_from_base(
        name: cs[:name],
        via_wizard: true,
        base_scheme_id: cs[:base_scheme_id],
        user_selectable: true,
      )
  end

  Theme.foundation_theme.set_default!

  dark_scheme_id = ColorScheme.where(base_scheme_id: "Dark").pick(:id)
  Theme.foundation_theme.update!(dark_color_scheme_id: dark_scheme_id) if dark_scheme_id.present?
end
