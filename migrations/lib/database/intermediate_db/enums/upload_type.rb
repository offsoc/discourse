# frozen_string_literal: true

# This file is auto-generated from the IntermediateDB schema. To make changes,
# update the "config/intermediate_db.yml" configuration file and then run
# `bin/cli schema generate` to regenerate this file.

module Migrations::Database::IntermediateDB::Enums
  module UploadType
    extend Migrations::Enum

    AVATAR = 1
    CARD_BACKGROUND = 2
    CUSTOM_EMOJI = 3
    PROFILE_BACKGROUND = 4
  end
end
