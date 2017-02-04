{-# LANGUAGE CPP #-}
{-# OPTIONS_GHC -fno-warn-missing-import-lists #-}
{-# OPTIONS_GHC -fno-warn-implicit-prelude #-}
module Paths_cabal_install (
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
version = Version [1,25,0,0] []
bindir, libdir, dynlibdir, datadir, libexecdir, sysconfdir :: FilePath

bindir     = "/home/travis/.cabal/bin"
libdir     = "/home/travis/.cabal/lib/x86_64-linux-ghc-7.8.4/.fake.cabal-install-1.25.0.0"
dynlibdir  = "/home/travis/.cabal/lib/x86_64-linux-ghc-7.8.4"
datadir    = "/home/travis/.cabal/share/x86_64-linux-ghc-7.8.4/cabal-install-1.25.0.0"
libexecdir = "/home/travis/.cabal/libexec"
sysconfdir = "/home/travis/.cabal/etc"

getBinDir, getLibDir, getDynLibDir, getDataDir, getLibexecDir, getSysconfDir :: IO FilePath
getBinDir = catchIO (getEnv "cabal_install_bindir") (\_ -> return bindir)
getLibDir = catchIO (getEnv "cabal_install_libdir") (\_ -> return libdir)
getDynLibDir = catchIO (getEnv "cabal_install_dynlibdir") (\_ -> return dynlibdir)
getDataDir = catchIO (getEnv "cabal_install_datadir") (\_ -> return datadir)
getLibexecDir = catchIO (getEnv "cabal_install_libexecdir") (\_ -> return libexecdir)
getSysconfDir = catchIO (getEnv "cabal_install_sysconfdir") (\_ -> return sysconfdir)

getDataFileName :: FilePath -> IO FilePath
getDataFileName name = do
  dir <- getDataDir
  return (dir ++ "/" ++ name)
