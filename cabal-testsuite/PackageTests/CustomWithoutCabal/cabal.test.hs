import Test.Cabal.Prelude
main = cabalTest $ do
    r <- fails $ cabal' "new-build" []
    assertOutputContains "My custom Setup" r
