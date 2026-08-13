{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}

-- | The JSON representation of the violations, as written on stdout by the
-- @--json@ argument.
--
-- Note: those are plain functions rather than 'Data.Aeson.ToJSON' instances so
-- that the wire format stays here, instead of leaking into 'Krank.Types'.
module Krank.Formatter.Json
  ( encodeViolations,
  )
where

import Data.Aeson (Value, object, (.=))
import Data.Aeson.Text (encodeToLazyText)
import Data.Text (Text)
import qualified Data.Text.Lazy as Text.Lazy
import Krank.Types

encodeViolations ::
  [Violation] ->
  Text
encodeViolations violations = Text.Lazy.toStrict (encodeToLazyText (map violationToJSON violations)) <> "\n"

violationToJSON ::
  Violation ->
  Value
violationToJSON Violation {checker, subject, level, message, location} =
  object
    [ "checker" .= checker,
      "subject" .= subject,
      "level" .= violationLevelToJSON level,
      "message" .= message,
      "location" .= sourcePosToJSON location
    ]

violationLevelToJSON ::
  ViolationLevel ->
  Value
violationLevelToJSON = \case
  Info -> "info"
  Warning -> "warning"
  Error -> "error"

sourcePosToJSON ::
  SourcePos ->
  Value
sourcePosToJSON SourcePos {file, lineNumber, colNumber} =
  object
    [ "file" .= file,
      "line" .= lineNumber,
      "column" .= colNumber
    ]
