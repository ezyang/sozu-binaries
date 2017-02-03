{-# LANGUAGE CPP #-}
{-# OPTIONS_GHC -fno-warn-missing-import-lists #-}
{-# OPTIONS_GHC -fno-warn-implicit-prelude #-}
module Paths_hackage_security (
    version,
    getBinDir, getLibDir, getDynLibDir, getDataDir, getLibexecDir,
    getDataFileName, getSysconfDir
  ) where

import qualified Control.Exception as Exception
import Data.Version (Version(..))
import System.Environment (getEnv)
import Prelude

#if defined(VERSION_base)

#if MIN_VERSION_base(4,0,0)
catchIO :: IO a -> (Exception.IOException -> IO a) -> IO a
#else
catchIO :: IO a -> (Exception.Exception -> IO a) -> IO a
#endif

#else
catchIO :: IO a -> (Exception.IOException -> IO a) -> IO a
#endif
catchIO = Exception.catch

version :: Version
version = Version [0,5,2,2] []
bindir, libdir, dynlibdir, datadir, libexecdir, sysconfdir :: FilePath

bindir     = "/home/travis/.cabal/bin"
libdir     = "/home/travis/.cabal/lib/x86_64-linux-ghc-7.10.3/.fake.hackage-security-0.5.2.2"
dynlibdir  = "/home/travis/.cabal/lib/x86_64-linux-ghc-7.10.3"
datadir    = "/home/travis/.cabal/share/x86_64-linux-ghc-7.10.3/hackage-security-0.5.2.2"
libexecdir = "/home/travis/.cabal/libexec"
sysconfdir = "/home/travis/.cabal/etc"

getBinDir, getLibDir, getDynLibDir, getDataDir, getLibexecDir, getSysconfDir :: IO FilePath
getBinDir = catchIO (getEnv "hackage_security_bindir") (\_ -> return bindir)
getLibDir = catchIO (getEnv "hackage_security_libdir") (\_ -> return libdir)
getDynLibDir = catchIO (getEnv "hackage_security_dynlibdir") (\_ -> return dynlibdir)
getDataDir = catchIO (getEnv "hackage_security_datadir") (\_ -> return datadir)
getLibexecDir = catchIO (getEnv "hackage_security_libexecdir") (\_ -> return libexecdir)
getSysconfDir = catchIO (getEnv "hackage_security_sysconfdir") (\_ -> return sysconfdir)

getDataFileName :: FilePath -> IO FilePath
getDataFileName name = do
  dir <- getDataDir
  return (dir ++ "/" ++ name)
