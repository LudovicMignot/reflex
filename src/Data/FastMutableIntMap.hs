{-# LANGUAGE DeriveFunctor #-}
{-# LANGUAGE DeriveFoldable #-}
{-# LANGUAGE DeriveTraversable #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE TypeFamilies #-}
module Data.FastMutableIntMap
  ( FastMutableIntMap
  , new
  , newEmpty
  , insert
  , isEmpty
  , getFrozenAndClear
  , size
  , applyPatch
  , PatchIntMap (..)
  , traverseIntMapPatchWithKey
  , lookup
  , forIntersectionWithImmutable_
  , for_
  , patchIntMapNewElements
  , patchIntMapNewElementsMap
  , getDeletions
  ) where

--TODO: Pure JS version
--TODO: Fast copy to FastIntMap
--TODO: Fast patch type

import Prelude hiding (lookup)
import Data.IORef
import Data.IntMap.Strict (IntMap)
import qualified Data.IntMap.Strict as IntMap
import Data.Maybe
import Reflex.Patch.Class
import Data.Foldable (traverse_)
import Control.Monad.IO.Class

newtype FastMutableIntMap a = FastMutableIntMap (IORef (IntMap a))

new :: IntMap a -> IO (FastMutableIntMap a)
new m = FastMutableIntMap <$> newIORef m

newEmpty :: IO (FastMutableIntMap a)
newEmpty = FastMutableIntMap <$> newIORef IntMap.empty

insert :: FastMutableIntMap a -> Int -> a -> IO ()
insert (FastMutableIntMap r) k v = modifyIORef' r $ IntMap.insert k v

lookup :: FastMutableIntMap a -> Int -> IO (Maybe a)
lookup (FastMutableIntMap r) k = IntMap.lookup k <$> readIORef r

forIntersectionWithImmutable_ :: MonadIO m => FastMutableIntMap a -> IntMap b -> (a -> b -> m ()) -> m ()
forIntersectionWithImmutable_ (FastMutableIntMap r) b f = do
  a <- liftIO $ readIORef r
  traverse_ (uncurry f) $ IntMap.intersectionWith (,) a b

for_ :: MonadIO m => FastMutableIntMap a -> (a -> m ()) -> m ()
for_ (FastMutableIntMap r) f = do
  a <- liftIO $ readIORef r
  traverse_ f a

isEmpty :: FastMutableIntMap a -> IO Bool
isEmpty (FastMutableIntMap r) = IntMap.null <$> readIORef r

size :: FastMutableIntMap a -> IO Int
size (FastMutableIntMap r) = IntMap.size <$> readIORef r

-- | Make an immutable snapshot of the datastructure and clear it
getFrozenAndClear :: FastMutableIntMap a -> IO (IntMap a)
getFrozenAndClear (FastMutableIntMap r) = do
  result <- readIORef r
  writeIORef r IntMap.empty
  return result

applyPatch :: FastMutableIntMap a -> PatchIntMap a -> IO (IntMap a)
applyPatch (FastMutableIntMap r) p@(PatchIntMap m) = do
  v <- readIORef r
  writeIORef r $! applyAlways p v
  return $ IntMap.intersection v m

newtype PatchIntMap a = PatchIntMap (IntMap (Maybe a)) deriving (Functor, Foldable, Traversable, Monoid)

instance Patch (PatchIntMap a) where
  type PatchTarget (PatchIntMap a) = IntMap a
  apply (PatchIntMap p) v = if IntMap.null p then Nothing else Just $
    let removes = IntMap.filter isNothing p
        adds = IntMap.mapMaybe id p
    in IntMap.union adds $ v `IntMap.difference` removes

traverseIntMapPatchWithKey :: Applicative t => (Int -> a -> t b) -> PatchIntMap a -> t (PatchIntMap b)
traverseIntMapPatchWithKey f (PatchIntMap m) = PatchIntMap <$> IntMap.traverseWithKey (\k mv -> traverse (f k) mv) m

patchIntMapNewElements :: PatchIntMap a -> [a]
patchIntMapNewElements (PatchIntMap m) = catMaybes $ IntMap.elems m

patchIntMapNewElementsMap :: PatchIntMap a -> IntMap a
patchIntMapNewElementsMap (PatchIntMap m) = IntMap.mapMaybe id m

getDeletions :: PatchIntMap v -> IntMap v' -> IntMap v'
getDeletions (PatchIntMap m) v = IntMap.intersection v m
