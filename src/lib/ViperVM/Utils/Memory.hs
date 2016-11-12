{-# LANGUAGE ForeignFunctionInterface #-}

-- | Memory utilities
module ViperVM.Utils.Memory
   ( memCopy
   , memSet
   , allocaArrays
   , peekArrays
   , pokeArrays
   , withArrays
   , withMaybeOrNull
   )
where

import ViperVM.Format.Binary.Word
import ViperVM.Format.Binary.Ptr
import ViperVM.Format.Binary.Storable
import ViperVM.Utils.Flow

-- | Copy memory
memCopy :: MonadIO m => Ptr a -> Ptr b -> Word64 -> m ()
memCopy dest src size = liftIO (void (memcpy dest src size))

{-# INLINE memCopy #-}

-- | memcpy
foreign import ccall unsafe memcpy  :: Ptr a -> Ptr b -> Word64 -> IO (Ptr c)



-- | Set memory
memSet :: MonadIO m => Ptr a -> Word64 -> Word8 -> m ()
memSet dest size fill = liftIO (void (memset dest fill size))

{-# INLINE memSet #-}

-- | memset
foreign import ccall unsafe memset  :: Ptr a -> Word8 -> Word64 -> IO (Ptr c)


-- | Allocate several arrays
allocaArrays :: (Storable s, Integral a) => [a] -> ([Ptr s] -> IO b) -> IO b
allocaArrays sizes f = go [] sizes
   where
      go as []     = f (reverse as)
      go as (x:xs) = allocaArray (fromIntegral x) $ \a -> go (a:as) xs

-- | Peek several arrays
peekArrays :: (Storable s, Integral a) => [a] -> [Ptr s] -> IO [[s]]
peekArrays szs ptrs = mapM f (szs `zip` ptrs)
   where
      f (sz,p) = peekArray (fromIntegral sz) p

-- | Poke several arrays
pokeArrays :: (Storable s) => [Ptr s] -> [[s]] -> IO ()
pokeArrays ptrs vs = mapM_ f (ptrs `zip` vs)
   where
      f = uncurry pokeArray

-- | Allocate several arrays
withArrays :: (Storable s) => [[s]] -> ([Ptr s] -> IO b) -> IO b
withArrays vs f = go [] vs
   where
      go as []     = f (reverse as)
      go as (x:xs) = withArray x $ \a -> go (a:as) xs

-- | Execute f with a pointer to 'a' or NULL
withMaybeOrNull ::
   ( Storable a
   , MonadInIO m
   ) => Maybe a -> (Ptr a -> m b) -> m b
withMaybeOrNull s f = case s of
   Nothing -> f nullPtr
   Just x  -> with x f
