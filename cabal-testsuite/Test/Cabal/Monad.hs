{-# LANGUAGE ScopedTypeVariables #-}

-- | The test monad
module Test.Cabal.Monad (
    -- * High-level runners
    setupAndCabalTest,
    setupTest,
    cabalTest,
    -- * The monad
    TestM,
    runTestM,
    -- * Helper functions
    programPathM,
    requireProgramM,
    isAvailableProgram,
    hackageRepoToolProgram,
    cabalProgram,
    -- * The test environment
    TestEnv(..),
    getTestEnv,
    -- * Derived values from 'TestEnv'
    testCurrentDir,
    testWorkDir,
    testPrefixDir,
    testDistDir,
    testPackageDbDir,
    testHomeDir,
    testSandboxDir,
    testSandboxConfigFile,
    testRepoDir,
    testKeysDir,
    testUserCabalConfigFile,
    -- * Skipping tests
    skip,
    skipIf,
    skipUnless,
    skipExitCode,
    -- * Known broken tests
    expectedBroken,
    unexpectedSuccess,
    expectedBrokenExitCode,
    unexpectedSuccessExitCode,
    -- whenHasSharedLibraries,
    -- * Arguments (TODO: move me)
    CommonArgs(..),
    renderCommonArgs,
    commonArgParser,
) where

import Test.Cabal.Script
import Test.Cabal.Plan

import Distribution.Simple.Compiler (PackageDBStack, PackageDB(..), compilerFlavor)
import Distribution.Simple.Program.Db
import Distribution.Simple.Program
import Distribution.Simple.Configure
    ( getPersistBuildConfig, configCompilerEx )
import Distribution.Types.LocalBuildInfo

import Distribution.Verbosity

import qualified Control.Exception as E
import Control.Monad
import Control.Monad.Trans.Reader
import Control.Monad.IO.Class
import Data.Maybe
import Control.Applicative
import Data.Monoid
import System.Directory
import System.Exit
import System.FilePath
import System.IO.Error (isDoesNotExistError)
import Options.Applicative

data CommonArgs = CommonArgs {
        argCabalInstallPath    :: Maybe FilePath,
        argGhcPath             :: Maybe FilePath,
        argHackageRepoToolPath :: Maybe FilePath,
        argSkipSetupTests      :: Bool
    }

commonArgParser :: Parser CommonArgs
commonArgParser = CommonArgs
    <$> optional (option str
        ( help "Path to cabal-install executable to test"
       <> long "with-cabal"
       <> metavar "PATH"
        ))
    <*> optional (option str
        ( help "GHC to ask Cabal to use via --with-ghc flag"
       <> short 'w'
       <> long "with-ghc"
       <> metavar "PATH"
        ))
    <*> optional (option str
        ( help "Path to hackage-repo-tool to use for repository manipulation"
       <> long "with-hackage-repo-tool"
       <> metavar "PATH"
        ))
    <*> switch (long "skip-setup-tests" <> help "Skip setup tests")

renderCommonArgs :: CommonArgs -> [String]
renderCommonArgs args =
    maybe [] (\x -> ["--with-cabal",             x]) (argCabalInstallPath    args) ++
    maybe [] (\x -> ["--with-ghc",               x]) (argGhcPath             args) ++
    maybe [] (\x -> ["--with-hackage-repo-tool", x]) (argHackageRepoToolPath args) ++
    (if argSkipSetupTests args then ["--skip-setup-tests"] else [])

data TestArgs = TestArgs {
        testArgDistDir    :: FilePath,
        testArgScriptPath :: FilePath,
        testCommonArgs    :: CommonArgs
    }

testArgParser :: Parser TestArgs
testArgParser = TestArgs
    <$> option str
        ( help "Build directory of cabal-testsuite"
       <> long "builddir"
       <> metavar "DIR")
    <*> argument str ( metavar "FILE")
    <*> commonArgParser

skip :: TestM ()
skip = liftIO $ do
    putStrLn "SKIP"
    exitWith (ExitFailure skipExitCode)

skipIf :: Bool -> TestM ()
skipIf b = when b skip

skipUnless :: Bool -> TestM ()
skipUnless b = unless b skip

expectedBroken :: TestM ()
expectedBroken = liftIO $ do
    putStrLn "EXPECTED FAIL"
    exitWith (ExitFailure expectedBrokenExitCode)

unexpectedSuccess :: TestM ()
unexpectedSuccess = liftIO $ do
    putStrLn "UNEXPECTED OK"
    exitWith (ExitFailure unexpectedSuccessExitCode)

skipExitCode :: Int
skipExitCode = 64

expectedBrokenExitCode :: Int
expectedBrokenExitCode = 65

unexpectedSuccessExitCode :: Int
unexpectedSuccessExitCode = 66

setupAndCabalTest :: TestM () -> IO ()
setupAndCabalTest m = do
    run_cabal <- runTestM $ do
        env <- getTestEnv
        have_cabal <- isAvailableProgram cabalProgram
        skipIf (testSkipSetupTests env && not have_cabal)
        if not (testSkipSetupTests env)
          then do
            liftIO $ putStrLn "Test with Setup:"
            m
            return have_cabal
          else do
            liftIO $ putStrLn "Test with cabal-install:"
            withReaderT (\nenv -> nenv { testCabalInstallAsSetup = True }) m
            return False
    -- NB: This code is written in a slightly convoluted way
    -- so as to ensure that 'runTestM' is only called once if
    -- we are running without cabal, or running with
    -- @--skip-setup-tests@.  This is important on Windows,
    -- where the second invocation of 'runTestM' will blow
    -- away our previous working dir, but it doesn't work
    -- on Windows Server 2012 because someone still has
    -- a handle on the directory (permission denied.)
    --
    -- The CORRECT way to fix this problem is to allocate a
    -- distinct working directory for setup versus Cabal.  Would
    -- nicely tie into to properly supporting "modes" as a thing
    -- for test scripts (the idea is that a test script has a
    -- number of modes which can be run separately as distinct
    -- tests.)
    when run_cabal $ do
        liftIO $ putStrLn "Test with cabal-install:"
        cabalTest m

setupTest :: TestM () -> IO ()
setupTest m = runTestM $ do
    env <- getTestEnv
    skipIf (testSkipSetupTests env)
    m

cabalTest :: TestM () -> IO ()
cabalTest m = runTestM $ do
    skipUnless =<< isAvailableProgram cabalProgram
    withReaderT (\nenv -> nenv { testCabalInstallAsSetup = True }) m

type TestM = ReaderT TestEnv IO

hackageRepoToolProgram :: Program
hackageRepoToolProgram = simpleProgram "hackage-repo-tool"

cabalProgram :: Program
cabalProgram = (simpleProgram "cabal") {
        -- Do NOT search for executable named cabal
        programFindLocation = \_ _ -> return Nothing
    }

-- | Run a test in the test monad according to program's arguments.
runTestM :: TestM a -> IO a
runTestM m = do
    args <- execParser (info testArgParser mempty)
    let dist_dir = testArgDistDir args
        (script_dir0, script_filename) = splitFileName (testArgScriptPath args)
        script_base = dropExtensions script_filename
    -- Canonicalize this so that it is stable across working directory changes
    script_dir <- canonicalizePath script_dir0
    lbi <- getPersistBuildConfig dist_dir
    let verbosity = normal -- TODO: configurable
    senv <- mkScriptEnv verbosity lbi
    -- Add test suite specific programs
    let program_db0 =
            addKnownPrograms
                ([hackageRepoToolProgram, cabalProgram] ++ builtinPrograms)
                (withPrograms lbi)
    -- Reconfigure according to user flags
    let cargs = testCommonArgs args
    program_db1 <-
        reconfigurePrograms verbosity
            ([("cabal", p) | p <- maybeToList (argCabalInstallPath cargs)] ++
             [("ghc",   p) | p <- maybeToList (argGhcPath cargs)] ++
             [("hackage-repo-tool", p)
                           | p <- maybeToList (argHackageRepoToolPath cargs)])
            [] -- --prog-options not supported ATM
            program_db0

    -- Reconfigure the rest of GHC
    program_db <- case argGhcPath cargs of
        Nothing -> return program_db1
        Just ghc_path -> do
            -- All the things that get updated paths from
            -- configCompilerEx.  The point is to make sure
            -- we reconfigure these when we need them.
            let program_db2 = unconfigureProgram "ghc"
                            . unconfigureProgram "ghc-pkg"
                            . unconfigureProgram "hsc2hs"
                            . unconfigureProgram "haddock"
                            . unconfigureProgram "hpc"
                            . unconfigureProgram "runghc"
                            . unconfigureProgram "gcc"
                            . unconfigureProgram "ld"
                            . unconfigureProgram "ar"
                            . unconfigureProgram "strip"
                            $ program_db1
            (_, _, program_db) <-
                configCompilerEx
                    (Just (compilerFlavor (compiler lbi)))
                    (Just ghc_path)
                    Nothing
                    program_db2
                    verbosity
            -- TODO: this actually leaves a pile of things unconfigured.
            -- Optimal strategy for us is to lazily configure them, so
            -- we don't pay for things we don't need.  A bit difficult
            -- to do in the current design.
            return program_db

    let db_stack =
            case argGhcPath (testCommonArgs args) of
                Nothing -> withPackageDB lbi
                -- Can't use the build package db stack since they
                -- are all for the wrong versions!  TODO: Make
                -- this configurable
                Just _  -> [GlobalPackageDB]
        env = TestEnv {
                    testSourceDir = script_dir,
                    testSubName = script_base,
                    testProgramDb = program_db,
                    testPackageDBStack = db_stack,
                    testVerbosity = verbosity,
                    testMtimeChangeDelay = Nothing,
                    testScriptEnv = senv,
                    testSetupPath = dist_dir </> "setup" </> "setup",
                    testSkipSetupTests =  argSkipSetupTests (testCommonArgs args),
                    testEnvironment =
                        -- Try to avoid Unicode output
                        [ ("LC_ALL", Just "C")
                        -- Hermetic builds (knot-tied)
                        , ("HOME", Just (testHomeDir env))],
                    testShouldFail = False,
                    testRelativeCurrentDir = ".",
                    testHavePackageDb = False,
                    testHaveSandbox = False,
                    testHaveRepo = False,
                    testCabalInstallAsSetup = False,
                    testCabalProjectFile = "cabal.project",
                    testPlan = Nothing
                }
    runReaderT (cleanup >> m) env
  where
    cleanup = do
        env <- getTestEnv
        onlyIfExists . removeDirectoryRecursive $ testWorkDir env
        -- NB: it's important to initialize this ourselves, as
        -- the default configuration hardcodes Hackage, which we do
        -- NOT want to assume for these tests (no test should
        -- hit Hackage.)
        liftIO $ createDirectoryIfMissing True (testHomeDir env </> ".cabal")
        ghc_path <- programPathM ghcProgram
        liftIO $ writeFile (testUserCabalConfigFile env)
               $ unlines [ "with-compiler: " ++ ghc_path ]

requireProgramM :: Program -> TestM ConfiguredProgram
requireProgramM program = do
    env <- getTestEnv
    (configured_program, _) <- liftIO $
        requireProgram (testVerbosity env) program (testProgramDb env)
    return configured_program

programPathM :: Program -> TestM FilePath
programPathM program = do
    fmap programPath (requireProgramM program)

isAvailableProgram :: Program -> TestM Bool
isAvailableProgram program = do
    env <- getTestEnv
    case lookupProgram program (testProgramDb env) of
        Just _ -> return True
        Nothing -> do
            -- It might not have been configured. Try to configure.
            progdb <- liftIO $ configureProgram (testVerbosity env) program (testProgramDb env)
            case lookupProgram program progdb of
                Just _  -> return True
                Nothing -> return False

-- | Run an IO action, and suppress a "does not exist" error.
onlyIfExists :: MonadIO m => IO () -> m ()
onlyIfExists m =
    liftIO $ E.catch m $ \(e :: IOError) ->
        if isDoesNotExistError e
            then return ()
            else E.throwIO e

data TestEnv = TestEnv
    -- UNCHANGING:

    {
    -- | Path to the test directory, as specified by path to test
    -- script.
      testSourceDir     :: FilePath
    -- | Test sub-name, used to qualify dist/database directory to avoid
    -- conflicts.
    , testSubName       :: String
    -- | Program database to use when we want ghc, ghc-pkg, etc.
    , testProgramDb     :: ProgramDb
    -- | Package database stack (actually this changes lol)
    , testPackageDBStack :: PackageDBStack
    -- | How verbose to be
    , testVerbosity     :: Verbosity
    -- | How long we should 'threadDelay' to make sure the file timestamp is
    -- updated correctly for recompilation tests.  Nothing if we haven't
    -- calibrated yet.
    , testMtimeChangeDelay :: Maybe Int
    -- | Script environment for runghc
    , testScriptEnv :: ScriptEnv
    -- | Setup script path
    , testSetupPath :: FilePath
    -- | Skip Setup tests?
    , testSkipSetupTests :: Bool

    -- CHANGING:

    -- | Environment override
    , testEnvironment   :: [(String, Maybe String)]
    -- | When true, we invert the meaning of command execution failure
    , testShouldFail    :: Bool
    -- | The current working directory, relative to 'testSourceDir'
    , testRelativeCurrentDir :: FilePath
    -- | Says if we've initialized the per-test package DB
    , testHavePackageDb  :: Bool
    -- | Says if we're working in a sandbox
    , testHaveSandbox :: Bool
    -- | Says if we've setup a repository
    , testHaveRepo :: Bool
    -- | Says if we're testing cabal-install as setup
    , testCabalInstallAsSetup :: Bool
    -- | Says what cabal.project file to use (probed)
    , testCabalProjectFile :: FilePath
    -- | Cached record of the plan metadata from a new-build
    -- invocation; controlled by 'withPlan'.
    , testPlan :: Maybe Plan
    }

getTestEnv :: TestM TestEnv
getTestEnv = ask

------------------------------------------------------------------------
-- * Directories

-- | The absolute path to the root of the package directory; it's
-- where the Cabal file lives.  This is what you want the CWD of cabal
-- calls to be.
testCurrentDir :: TestEnv -> FilePath
testCurrentDir env = testSourceDir env </> testRelativeCurrentDir env

-- | The absolute path to the directory containing all the
-- files for ALL tests associated with a test (respecting
-- subtests.)  To clean, you ONLY need to delete this directory.
testWorkDir :: TestEnv -> FilePath
testWorkDir env =
    testSourceDir env </> (testSubName env ++ ".dist")

-- | The absolute prefix where installs go.
testPrefixDir :: TestEnv -> FilePath
testPrefixDir env = testWorkDir env </> "usr"

-- | The absolute path to the build directory that should be used
-- for the current package in a test.
testDistDir :: TestEnv -> FilePath
testDistDir env = testWorkDir env </> "work" </> testRelativeCurrentDir env </> "dist"

-- | The absolute path to the shared package database that should
-- be used by all packages in this test.
testPackageDbDir :: TestEnv -> FilePath
testPackageDbDir env = testWorkDir env </> "packagedb"

-- | The absolute prefix where our simulated HOME directory is.
testHomeDir :: TestEnv -> FilePath
testHomeDir env = testWorkDir env </> "home"

-- | The absolute prefix of our sandbox directory
testSandboxDir :: TestEnv -> FilePath
testSandboxDir env = testWorkDir env </> "sandbox"

-- | The sandbox configuration file
testSandboxConfigFile :: TestEnv -> FilePath
testSandboxConfigFile env = testWorkDir env </> "cabal.sandbox.config"

-- | The absolute prefix of our local secure repository, which we
-- use to simulate "external" packages
testRepoDir :: TestEnv -> FilePath
testRepoDir env = testWorkDir env </> "repo"

-- | The absolute prefix of keys for the test.
testKeysDir :: TestEnv -> FilePath
testKeysDir env = testWorkDir env </> "keys"

-- | The user cabal config file
-- TODO: Not obviously working on Windows
testUserCabalConfigFile :: TestEnv -> FilePath
testUserCabalConfigFile env = testHomeDir env </> ".cabal" </> "config"
