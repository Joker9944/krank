{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE ViewPatterns #-}

import Control.Applicative (optional)
import Control.Exception (catch)
import Control.Monad.Reader
import qualified Data.Map as Map
import Data.Maybe
import qualified Data.Text as Text
import GHC.Exception
import Krank
import Krank.Types
import Options.Applicative (many, (<**>))
import qualified Options.Applicative as Opt
import PyF (fmt)
import System.Console.Pretty (supportsPretty)
import System.Environment (lookupEnv)
import System.Exit (exitFailure)
import System.IO (hPrint, hPutStrLn, hSetEncoding, stderr, stdout, utf8)
import System.Process
import Text.Regex.PCRE.Heavy
import Version (displayVersion)
import Control.Monad (unless)

data KrankOpts = KrankOpts
  { codeFilePaths :: [FilePath],
    krankConfig :: KrankConfig
  }

filesToParse :: Opt.Parser [FilePath]
filesToParse = many (Opt.argument Opt.str (Opt.metavar "FILES..." <> Opt.help "List of file to check. If empty, it will try to use `git ls-files`."))

githubKeyToParse :: Opt.Parser (Maybe GithubKey)
githubKeyToParse =
  optional
    ( GithubKey
        <$> Opt.strOption
          ( Opt.long "issuetracker-githubkey"
              <> Opt.metavar "PERSONAL_GITHUB_KEY"
              <> Opt.help "A github developer key to allow for more API calls or access to private github repo for the IssueTracker checker"
          )
    )

parseGitlabKey :: Opt.ReadM (GitlabHost, GitlabKey)
parseGitlabKey = Opt.eitherReader $ \(Text.pack -> s) -> case scan [re|^([^=]+)=(.+)$|] s of
  [(_, [x, y])] -> Right (GitlabHost x, GitlabKey y)
  _ -> Left [fmt|Unable to parse gitlab key=value from: {s}|]

gitlabKeyToParse :: Opt.Parser (Map.Map GitlabHost GitlabKey)
gitlabKeyToParse =
  Map.fromList
    <$> many
      ( Opt.option parseGitlabKey $
          Opt.long "issuetracker-gitlabhost"
            <> Opt.metavar "HOST=PERSONAL_GITLAB_KEY"
            <> Opt.help "A couple of gitlab host and developer key to allow reaching private gitlab repo for the IssueTracker checker. Can be specified multiple times."
      )

noColorParse :: Opt.Parser Bool
noColorParse =
  not
    <$> Opt.switch
      ( Opt.long "no-colors"
          <> Opt.help "Disable colored outputs. You can also set NO_COLOR environment variable."
      )

jsonOutputParse :: Opt.Parser Bool
jsonOutputParse =
  Opt.switch
    ( Opt.long "json"
        <> Opt.help "Write the violations to stdout as a JSON array instead of human readable text. Errors are still reported on stderr."
    )

versionParse :: Opt.Parser (a -> a)
versionParse =
  Opt.infoOption
    displayVersion
    ( Opt.long "version"
        <> Opt.help "Displays the version of the program"
    )

optionsParser :: Opt.Parser KrankOpts
optionsParser =
  KrankOpts
    <$> filesToParse
    <*> ( KrankConfig
            <$> githubKeyToParse
            <*> gitlabKeyToParse
            <*> Opt.switch
              ( Opt.long "dry-run"
                  <> Opt.help "Perform a dry run. Parse file, but do not execute HTTP requests"
              )
            <*> noColorParse
            <*> jsonOutputParse
        )

opts :: Opt.ParserInfo KrankOpts
opts =
  Opt.info
    (optionsParser <**> Opt.helper <**> versionParse)
    ( Opt.fullDesc
        <> Opt.progDesc "Checks the comments in FILES"
        <> Opt.header "krank - a comment linter / analytics tool"
    )

main :: IO ()
main = do
  -- The files krank reads are arbitrary bytes and the JSON output has to be
  -- valid UTF-8 whatever the locale is. Without this, a non ASCII character
  -- makes the write fail under a non UTF-8 locale, such as the LANG-less
  -- environment of most CI images.
  hSetEncoding stdout utf8
  hSetEncoding stderr utf8

  noColor <- isJust <$> lookupEnv "NO_COLOR"
  colorSupport <- supportsPretty

  let canUseColor = colorSupport && not noColor
  config <- Opt.customExecParser (Opt.prefs Opt.showHelpOnError) opts
  let kConfig =
        (krankConfig config)
          { useColors = useColors (krankConfig config) && canUseColor
          }

  -- If files are not explicitly listed, try `git ls-files` and `find`.
  files <- case codeFilePaths config of
    [] -> (lines <$> readProcess "git" ["ls-files"] "") `catch` (\(e :: SomeException) -> noGitFailure e)
    l -> pure l

  success <- runReaderT (unKrank $ runKrank files) kConfig
  unless success exitFailure

-- Note: those diagnostics go to stderr so that stdout stays a valid JSON
-- document when --json is used
noGitFailure :: SomeException -> IO [String]
noGitFailure e = do
  hPrint stderr e
  hPutStrLn stderr "`Git` was not found, trying to list files using `find`"
  (lines <$> readProcess "find" [""] "") `catch` findFailure

findFailure :: SomeException -> IO [FilePath]
findFailure e = do
  hPrint stderr e
  hPutStrLn stderr "`find` was not found, please pass file argument manually"
  pure []
