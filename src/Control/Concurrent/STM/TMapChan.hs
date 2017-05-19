module Control.Concurrent.STM.TMapChan
  ( TMapChan (..)
  , newTMapChan
  , insert, insertMany, insertFirst
  , lookup, tryLookup, lookupAll
  , observe, tryObserve, observeAll
  , delete, deleteAll
  , -- * Utils
    getTChan
  , setTChan
  , keys
  , broadcast
  , cloneAt, cloneAll, cloneAllUniquely
  ) where

import Prelude hiding (lookup)
import Data.Map.Lazy (Map)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Control.Monad (void, forM_)
import Control.Concurrent.STM (STM, atomically)
import Control.Concurrent.STM.TChan (TChan, newTChan, newTChanIO, writeTChan, readTChan, tryReadTChan, peekTChan, tryPeekTChan, unGetTChan)
import Control.Concurrent.STM.TVar (TVar, newTVar, readTVar, writeTVar, modifyTVar')


newtype TMapChan k a = TMapChan {runTMapChan :: TVar (Map k (TChan a))}

keys :: TMapChan k a -> STM [k]
keys (TMapChan m) = Map.keys <$> readTVar m

newTMapChan :: STM (TMapChan k a)
newTMapChan = TMapChan <$> newTVar Map.empty

insert :: Ord k => TMapChan k a -> k -> a -> STM ()
insert t k a = do
  c <- getTChan t k
  writeTChan c a

insertMany :: Ord k => TMapChan k a -> k -> [a] -> STM ()
insertMany t k as = forM_ as (insert t k)

-- | Inserts the element to the head of the stack, to be viewed next
insertFirst :: Ord k => TMapChan k a -> k -> a -> STM ()
insertFirst t k a = do
  c <- getTChan t k
  unGetTChan c a

-- | Blocks until there's a value available to remove from the mutlimap
lookup :: Ord k => TMapChan k a -> k -> IO a
lookup t k = do
  c <- atomically $ getTChan t k
  atomically $ readTChan c

tryLookup :: Ord k => TMapChan k a -> k -> IO (Maybe a)
tryLookup t k = do
  c <- atomically $ getTChan t k
  atomically $ tryReadTChan c

lookupAll :: Ord k => TMapChan k a -> k -> IO [a]
lookupAll t k = do
  mNext <- tryLookup t k
  case mNext of
    Nothing -> pure []
    Just next -> (next:) <$> lookupAll t k

-- | Blocks until there's a vale available to view, without removing it
observe :: Ord k => TMapChan k a -> k -> IO a
observe t k = do
  c <- atomically $ getTChan t k
  atomically $ peekTChan c

tryObserve :: Ord k => TMapChan k a -> k -> IO (Maybe a)
tryObserve t k = do
  c <- atomically $ getTChan t k
  atomically $ tryPeekTChan c

observeAll :: Ord k => TMapChan k a -> k -> IO [a]
observeAll t k = do
  mNext <- tryObserve t k
  case mNext of
    Nothing -> pure []
    Just next -> (:) next <$> observeAll t k


-- | Deletes the /next/ element in the map, if it exists. Doesn't block.
delete :: Ord k => TMapChan k a -> k -> IO ()
delete t k = void (tryLookup t k)

-- | Clears the queue at the key
deleteAll :: Ord k => TMapChan k a -> k -> IO ()
deleteAll t k = void (lookupAll t k)


-- * Utils


-- | Insert for every key
broadcast :: Ord k => TMapChan k a -> a -> STM ()
broadcast t@(TMapChan xs) a = do
  ks <- Map.keys <$> readTVar xs
  forM_ ks (\k -> insert t k a)


-- | Creates a new one if it doesn't already exist
getTChan :: Ord k => TMapChan k a -> k -> STM (TChan a)
getTChan (TMapChan t) k = do
  xs <- readTVar t
  case Map.lookup k xs of
    Nothing -> do
      c' <- newTChan
      writeTVar t (Map.insert k c' xs)
      pure c'
    Just c' -> pure c'


setTChan :: Ord k => TMapChan k a -> k -> TChan a -> STM ()
setTChan (TMapChan t) k c = modifyTVar' t (Map.insert k c)



cloneAt :: Ord k
        => TMapChan k a
        -> k -- ^ key to clone /from/
        -> k -- ^ key to clone /to/
        -> IO ()
cloneAt t@(TMapChan xs) kFrom kTo = do
  as <- observeAll t kFrom
  c <- newTChanIO
  atomically $
    forM_ as (writeTChan c)
  atomically $ modifyTVar' xs (Map.insert kTo c)

-- | Clones all the content for every key, by the key.
cloneAll :: Ord k => TMapChan k a -> k -> IO ()
cloneAll t@(TMapChan xs) k = do
  as <- atomically $ readTVar xs
  c <- newTChanIO
  forM_ (Map.keysSet as) $ \k' -> do
    as' <- observeAll t k'
    atomically $ forM_ as' (writeTChan c)
  atomically $ modifyTVar' xs (Map.insert k c)

-- | Clones all the content from every channel, and inserts the unique subset of them to `k`, in the order of their Ord instance
cloneAllUniquely :: ( Ord k
                    , Ord a
                    )
                  => TMapChan k a
                  -> k
                  -> IO ()
cloneAllUniquely t@(TMapChan xs) k = do
  as <- atomically $ readTVar xs
  c <- newTChanIO
  as' <- atomically $ newTVar Set.empty
  forM_ (Map.keysSet as) $ \k' -> do
    as'More <- Set.fromList <$> observeAll t k'
    atomically $ modifyTVar' as' (Set.union as'More)
  as'All <- atomically $ Set.toAscList <$> readTVar as'
  atomically $ forM_ as'All (writeTChan c)
  atomically $ modifyTVar' xs (Map.insert k c)
