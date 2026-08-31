# frozen_string_literal: true

OmarchyUI.configure do
  type :plugin
  id "izeesoft.config-prism"
  name "Config Prism"
  slug "config-prism"
  version "0.1.0"
  author "Adam Moussa Ali"
  license "MIT"
  description "Read-only Omarchy and Hyprland configuration drift explorer with reviewable explanations."
  entrypoint "main.rb"

  bar_widget do
    display_name "Config Prism"
    description "See exactly how your live Omarchy configuration differs from the packaged defaults."
    category "System"
    default_section :right
  end
end
