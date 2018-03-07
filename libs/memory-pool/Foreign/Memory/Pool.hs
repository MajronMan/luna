
module Foreign.Memory.Pool where

import Prologue

import qualified Foreign

import Foreign (Ptr, Storable, peek, poke)
import Foreign.Ptr.Utils (SomePtr)
import Foreign.Storable.Utils (sizeOf')
import qualified Foreign.Ptr as Ptr
import qualified Foreign.Marshal.Utils as Ptr

import qualified Foreign.Memory.Manager as Mgr


type MemPool = Mgr.MemoryManager


allocPtr :: forall a m. (MonadIO m, Storable a) => m (Ptr a)
allocPtr = liftIO Foreign.malloc ; {-# INLINE allocPtr #-}

allocBytes :: forall a m. MonadIO m => Int -> m (Ptr a)
allocBytes t = liftIO $ Foreign.mallocBytes t ; {-# INLINE allocBytes #-}

unsafeNull :: MemPool
unsafeNull = Mgr.unsafeNull ; {-# INLINE unsafeNull #-}

new :: MonadIO m => Int -> m MemPool
new = Mgr.newManager ; {-# INLINE new #-}

alloc :: MonadIO m => MemPool -> m (Ptr a)
alloc = Mgr.newItem ; {-# INLINE alloc #-}


--
-- import Foreign.Marshal.Alloc (mallocBytes)
-- import Foreign (Ptr, nullPtr, plusPtr, castPtr)
-- import Foreign.Storable.Utils (sizeOf')
--
-- import Control.Monad.State hiding (MonadIO, liftIO, return, fail)
--
-- import Foreign (Storable, poke, peek)
-- --
-- -- newtype Block = Block Int deriving (Show)
-- -- makeLenses ''Block
-- --
-- --
-- -- instance Storable a => Storable (UniCore a) where
-- --     sizeOf    a = unwrap a ; {-# INLINE sizeOf    #-}
-- --     alignment _ = chunkSize     ; {-# INLINE alignment #-}
-- --     peek ptr = peek (intPtr ptr) >>= \case
-- --         0 -> UVar <$> peekByteOff ptr chunkSize
-- --         1 -> UAcc <$> peekByteOff ptr chunkSize
-- --         _ -> error "Unrecognized constructor"
-- --     {-# INLINE peek #-}
-- --     poke ptr = \case
-- --         UVar !a -> poke (intPtr ptr) 0 >> pokeByteOff ptr chunkSize a
-- --         UAcc !a -> poke (intPtr ptr) 1 >> pokeByteOff ptr chunkSize a
-- --     {-# INLINE poke #-}
--
-- type Ptr' = Ptr ()
--
-- -- data Block = Block
-- --     { _size     :: {-# UNPACK #-} !Int
-- --     , _startPtr :: {-# UNPACK #-} !Ptr'
-- --     } deriving (Show)
-- -- makeLenses ''Block
-- --
-- --
-- -- newBlock :: MonadIO m => Int -> m Block
-- -- newBlock s = liftIO $ Block s <$> mallocBytes s ; {-# INLINE newBlock #-}
-- --
--
-- data Pool = Pool
--     { _elemBytes :: {-# UNPACK #-} !Int
--     , _blockSize :: {-# UNPACK #-} !Int
--     , _blocksNum :: {-# UNPACK #-} !Int
--     , _blocks    :: ![Ptr']
--     , _freePtrs  :: ![Ptr']
--     } deriving (Show)
-- makeLenses ''Pool
--
-- emptyPool :: Int -> Int -> Pool
-- emptyPool elBytes blkSize = Pool elBytes blkSize 0 mempty mempty
-- {-# INLINE emptyPool #-}
--
--
--
-- type MemoryPoolT = StateT Pool
-- type MonadMemoryPool m = (MonadState Pool m, MonadIO m, MonadFail m)
--
--
--
-- evalMemoryPoolT :: Monad m => Int -> Int -> MemoryPoolT m a -> m a
-- evalMemoryPoolT elBytes blkSize = flip evalStateT (emptyPool elBytes blkSize)
--
-- allocBlock :: MonadMemoryPool m => m ()
-- allocBlock = do
--     pool <- get
--     let elSize = pool ^. elemBytes
--         els    = pool ^. blockSize
--     block <- liftIO $ mallocBytes (els * elSize)
--     let newPtrs = plusPtr block . (* elSize) <$> [0..(els - 1)]
--         pool'   = pool & blocksNum %~ (+1)
--                        & blocks    %~ (block:)
--                        & freePtrs  %~ (<> newPtrs)
--     put pool'
-- {-# INLINE allocBlock #-}
--
-- allocPtr :: MonadMemoryPool m => m Ptr'
-- allocPtr = allocPtr' (allocBlock >> allocPtr' allocErr) where
--     allocErr    = fail "Cannot allocate memory"
--     allocPtr' f = do
--         pool <- get
--         case pool ^. freePtrs of
--             (p:ps) -> put (pool & freePtrs .~ ps) >> pure p
--             []     -> f
-- {-# INLINE allocPtr #-}
--
-- test :: IO ()
-- test = evalMemoryPoolT 2 3 $ do
--     print =<< allocPtr
--     print =<< allocPtr
--     print =<< allocPtr
--     print =<< allocPtr
--     print =<< allocPtr
--     print =<< allocPtr
--     print =<< allocPtr
--     pool <- get
--     pprint pool
--
--
--
--
-- type MemoryPoolT2 = StateT Pool2
-- type MonadMemoryPool2 m = (MonadState Pool2 m, MonadIO m, MonadFail m)
--
-- data Pool2 = Pool2
--     { _elemSize2   :: {-# UNPACK #-} !Int
--     , _blockElems2 :: {-# UNPACK #-} !Int
--     , _blocksNum2  :: {-# UNPACK #-} !Int
--     , _blocks2     :: ![Ptr']
--     , _headPtr2    :: !Ptr'
--     } deriving (Show)
-- makeLenses ''Pool2
--
-- emptyPool2 :: Int -> Int -> Pool2
-- emptyPool2 elBytes blkSize = Pool2 elBytes blkSize 0 mempty nullPtr
-- {-# INLINE emptyPool2 #-}
--
--
-- ptrSize :: Int
-- ptrSize = sizeOf' @Ptr'
--
--
-- -- The 'initPtrChain' function initializes Memory Pool writing to each chunk
-- -- pointer to the address of the next chunk. Such linked list is used while
-- -- reserving pointers from the pool. Following table illustrates the process:
-- --
-- --                 |  elSize  |
-- --                 v          v
-- --         head    0x0       0x2       0x4       0x6
-- --        +-----+  +---------+---------+---------+----------+
-- -- init:  | 0x0 |  |0x2      |0x4      |0x6      |nullPtr   |
-- --        +-----+  +---------+---------+---------+----------+
-- -- alloc: | 0x4 |  | ...     |0x4      |0x6      |nullPtr   |
-- --        +-----+  +---------+---------+---------+----------+
-- -- alloc: | 0x6 |  | ...     |...      |0x6      |nullPtr   |
-- --        +-----+  +---------+---------+---------+----------+
-- -- free:  | 0x0 |  | 0x4     |...      |0x6      |nullPtr   |
-- --        +-----+  +---------+---------+---------+----------+
-- --
-- initPtrChain :: MonadIO m => Int -> Ptr a -> Int -> m ()
-- initPtrChain elSize headPtr elems = liftIO $ go headPtr (elems - 1) where
--     go ptr 0 = poke (castPtr ptr) nullPtr
--     go ptr i = do
--         let nptr = plusPtr ptr elSize
--         poke (castPtr ptr) nptr
--         go nptr (i - 1)
-- {-# INLINE initPtrChain #-}
--
--
-- allocAndReplacePoolBlock :: MonadMemoryPool2 m => m ()
-- allocAndReplacePoolBlock = do
--     -- pool <- get
--     -- let elSize    = pool ^. elemSize2
--     --     elems     = pool ^. blockElems2
--     --     blockSize = elems * elSize
--     -- block <- liftIO $ mallocBytes (elems * elSize)
--     -- liftIO $ poke (castPtr $ pool ^. headPtr2) block
--     -- initPtrChain elSize block elems
--     -- let pool' = pool & blocksNum2 %~ (+1)
--     --                  & blocks2    %~ (block:)
--     -- put pool'
--     return ()
-- {-# INLINE allocAndReplacePoolBlock #-}
-- -- --
-- --
-- --
-- -- type MemoryPoolT = StateT Pool
-- -- type MonadMemoryPool m = (MonadState Pool m, MonadIO m, MonadFail m)
-- --
-- --
-- --
-- evalMemoryPoolT2 :: Monad m => Int -> Int -> MemoryPoolT2 m a -> m a
-- evalMemoryPoolT2 elBytes blkSize = flip evalStateT (emptyPool2 elBytes blkSize)
-- --
-- -- allocBlock :: MonadMemoryPool m => m ()
-- -- allocBlock = do
-- --     pool <- get
-- --     let elSize = pool ^. elemBytes
-- --         els    = pool ^. blockSize
-- --     block <- liftIO $ mallocBytes (els * elSize)
-- --     let newPtrs = plusPtr block . (* elSize) <$> [0..(els - 1)]
-- --         pool'   = pool & blocksNum %~ (+1)
-- --                        & blocks    %~ (block:)
-- --                        & freePtrs  %~ (<> newPtrs)
-- --     put pool'
-- -- {-# INLINE allocBlock #-}
-- --
-- allocPtr2 :: MonadMemoryPool2 m => m Ptr'
-- allocPtr2 = allocPtr' (allocAndReplacePoolBlock >> allocPtr' allocErr) where
--     allocErr    = fail "Cannot allocate memory"
--     allocPtr' f = do
--         pool <- get
--         nPtr <- liftIO $ peek (castPtr $ pool ^. headPtr2)
--         if nPtr == nullPtr then f else do
--             nnPtr <- liftIO $ peek $ (castPtr nPtr :: Ptr Ptr')
--             liftIO $ poke (castPtr $ pool ^. headPtr2) nnPtr
--             return nPtr
-- {-# INLINE allocPtr2 #-}
--
-- test2 :: IO ()
-- test2 = evalMemoryPoolT2 2 3 $ do
--     allocAndReplacePoolBlock
--     -- print =<< allocPtr2
-- --     print =<< allocPtr
-- --     print =<< allocPtr
-- --     print =<< allocPtr
-- --     print =<< allocPtr
-- --     print =<< allocPtr
-- --     print =<< allocPtr
--     pool <- get
--     pprint pool
