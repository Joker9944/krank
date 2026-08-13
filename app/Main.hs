{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE ViewPatterns #-}

import Control.Applicative (optional)
import Control.Exception (catch)
import Control.Monad (filterM, when)
import Control.Monad.Reader
import Data.List (stripPrefix)
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
import System.Directory (doesFileExist)
import System.Environment (lookupEnv)
import System.Exit (ExitCode (..), exitWith)
import System.IO (hPrint, hPutStrLn, hSetEncoding, stderr, stdout, utf8)
import System.Process
import Text.Regex.PCRE.Heavy
import Version (displayVersion)

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
        <> Opt.failureCode 2
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
    [] -> do
      discovered <- (Just . lines <$> readProcess "git" ["ls-files"] "") `catch` (\(e :: SomeException) -> noGitFailure e)
      -- `git ls-files` lists submodules which are tracked but locally deleted.
      traverse (filterM doesFileExist) discovered
    l -> pure (Just l)

  case files of
    -- The list of files to check could not be established, so krank has no
    -- idea of what it was supposed to look at
    Nothing -> exitWith (ExitFailure 2)
    Just filesToCheck -> do
      outcome <- runReaderT (unKrank $ runKrank filesToCheck) kConfig
      case outcome of
        Clean -> pure ()
        Findings -> exitWith (ExitFailure 1)
        Failure -> exitWith (ExitFailure 2)

-- | Note: those diagnostics go to stderr so that stdout stays a valid JSON
-- document when --json is used.
-- 'Nothing' means that the file list could not be established, which is
-- different from an empty list of files to check.
noGitFailure :: SomeException -> IO (Maybe [String])
noGitFailure e = do
  hPrint stderr e
  hPutStrLn stderr "`Git` was not found, trying to list files using `find`"
  (Just . map dropFindPathPrefix . lines <$> readProcess "find" [".", "-type", "f"] "") `catch` findFailure

findFailure :: SomeException -> IO (Maybe [FilePath])
findFailure e = do
  hPrint stderr e
  hPutStrLn stderr "`find` was not found, please pass file argument manually"
  pure Nothing

dropFindPathPrefix :: FilePath -> FilePath
dropFindPathPrefix path = fromMaybe path (stripPrefix "./" path)
