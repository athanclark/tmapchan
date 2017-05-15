{-# LANGUAGE
    ScopedTypeVariables
  , TupleSections
  #-}

module Main where


import Test.Tasty
import Test.Tasty.Hspec
import Test.Hspec
import Control.Monad (void)
import Control.Concurrent.Async
import Control.Concurrent
import Control.Concurrent.STM
import qualified Control.Concurrent.STM.TMapChan as TMapChan
import Control.Concurrent.STM.TMapChan (TMapChan, newTMapChan)


main :: IO ()
main = do
  (chan :: TMapChan Int Int) <- atomically newTMapChan

  insLookup <- testSpec "Insert/Lookup" $ do
    (k,v1,v2) <- runIO $ atomically $ do
      TMapChan.insert chan 0 0
      (0,0,) <$> TMapChan.lookup chan 0
    it "is available as it was put in" $ v1 == v2 && v1 == 0

  lookupInsLater <- testSpec "Lookup/Insert Later" $ do
    (k,v1,v2) <- runIO $ do
      void $ async $ do
        threadDelay 1000000
        atomically $ TMapChan.insert chan 1 1
      atomically $
        (1,1,) <$> TMapChan.lookup chan 1
    it "is available as it was put in, but later" $ v1 == v2 && v1 == 1

  defaultMain $ testGroup "TMapChan"
    [ testGroup "Single Thread"
        [ insLookup
        , lookupInsLater
        ]
    ]
