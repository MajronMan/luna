{-# LANGUAGE OverloadedStrings #-}

module Luna.Pass.Resolution.MethodResolution where

import Luna.Prelude hiding (String, s, new, (<+>))
import OCI.Pass     hiding (compile)
import Data.Maybe   (isJust)

import OCI.IR.Combinators

import qualified Data.Map as Map
import OCI.IR.Name           (Name)
import qualified Luna.IR.Expr as Term

import           Luna.Builtin.Data.Function as Function
import           Luna.Builtin.Data.Module   as Module
import           Luna.Builtin.Data.Module   (Imports)
import           Luna.Builtin.Data.Class    as Class
import Luna.IR                              hiding (Function, Import)
import OCI.IR.Class (Import)

import Luna.Pass.Resolution.FunctionResolution (ImportError(..))

import Luna.Pass.Data.ExprRoots
import Luna.Pass.Resolution.Data.CurrentTarget
import Luna.Pass.Resolution.Data.UnresolvedAccs
import Luna.Pass.Inference.Data.SimplifierQueue
import Luna.Pass.Inference.Data.MergeQueue
import Luna.Pass.Inference.Data.Unifications


data AccessorFunction
type instance Abstract   AccessorFunction = AccessorFunction
type instance Inputs     Net   AccessorFunction = '[AnyExpr, AnyExprLink]
type instance Inputs     Layer AccessorFunction = '[AnyExpr // Model, AnyExprLink // Model, AnyExpr // Type, AnyExpr // Succs, AnyExpr // Errors, AnyExpr // Requester]
type instance Inputs     Attr  AccessorFunction = '[UnresolvedAccs, SimplifierQueue, Unifications, Imports, MergeQueue, CurrentTarget, ExprRoots]
type instance Inputs     Event AccessorFunction = '[]

type instance Outputs    Net   AccessorFunction = '[AnyExpr, AnyExprLink]
type instance Outputs    Layer AccessorFunction = '[AnyExpr // Model, AnyExprLink // Model, AnyExpr // Succs, AnyExpr // Type, AnyExpr // Errors, AnyExpr // Requester]
type instance Outputs    Attr  AccessorFunction = '[UnresolvedAccs, SimplifierQueue, Unifications, MergeQueue]
type instance Outputs    Event AccessorFunction = '[New // AnyExpr, New // AnyExprLink, Import // AnyExpr, Import // AnyExprLink, Delete // AnyExpr, Delete // AnyExprLink, OnDeepDelete // AnyExpr]

type instance Preserves        AccessorFunction = '[]


data AccessorError = MethodNotFound Name Name
                   | AmbiguousType
    deriving (Eq, Show)

importErrorDoc :: Name -> Name -> Text
importErrorDoc n cl = "Can't find method " <> convert (show n) <> " of " <> convert (show cl)

runMethodResolution :: MonadPassManager m => SubPass AccessorFunction m Bool
runMethodResolution = do
    accs <- getAccs <$> getAttr @UnresolvedAccs
    res <- forM accs $ \acc -> do
        result <- importAccessor acc
        case result of
            False -> return $ Just acc
            _     -> return Nothing
    putAttr @UnresolvedAccs $ putAccs $ catMaybes res
    return $ any isNothing res

destructMonad :: (MonadRef m, MonadIO m, MonadPassManager m) => Expr Draft -> SubPass AccessorFunction m (Expr Draft, Expr Draft)
destructMonad e = do
    Term (Term.Monadic t m) <- readTerm $ (unsafeGeneralize e :: Expr Monadic)
    (,) <$> source t <*> source m

importAccessor :: MonadPassManager m => Expr Monadic -> SubPass AccessorFunction m Bool
importAccessor tacc = do
    Term (Term.Monadic ac' _) <- readTerm tacc
    ac <- source ac'
    matchExpr ac $ \case
        Acc tv n -> do
            tv' <- source tv
            (tgtT, _) <- destructMonad tv'
            req <- mapM source =<< getLayer @Requester tacc
            matchExpr tgtT $ \case
                Cons cls _args -> importMethod cls n req >>= \case
                    Left e      -> do
                        forM_ req $ \requester -> do
                            modifyLayer_ @Errors requester (e <>)
                        reconnectLayer' @Requester (Nothing :: Maybe (Expr Draft)) tacc
                        return True
                    Right root  -> do
                        tap <- app root tv'
                        replace tap ac
                        modifyAttr_ @SimplifierQueue $ wrapped %~ (generalize tacc :)
                        return True
                _ -> return False

importMethod :: MonadPassManager m => Name -> Name -> Maybe (Expr Draft) -> SubPass AccessorFunction m (Either [CompileError] SomeExpr)
importMethod className methodName newReq = do
    current <- fromCurrentTarget className methodName
    case current of
        Just a  -> return $ Right a
        Nothing -> importMethodFromImports className methodName newReq

fromCurrentTarget :: MonadPassManager m => Name -> Name -> SubPass AccessorFunction m (Maybe SomeExpr)
fromCurrentTarget className methodName = do
    currentTgt <- getAttr @CurrentTarget
    root       <- (head . unwrap <$> getAttr @ExprRoots) >>= getLayer @Type >>= source
    return $ case currentTgt of
        TgtMethod c m -> if c == className && m == methodName then Just $ generalize root else Nothing
        _             -> Nothing

importMethodFromImports :: MonadPassManager m => Name -> Name -> Maybe (Expr Draft) -> SubPass AccessorFunction m (Either [CompileError] SomeExpr)
importMethodFromImports className methodName newReq = do
    imports <- getAttr @Imports
    let  method = (lookupClass methodName className >=> lookupMethod methodName className) imports
    case method of
        Left err -> return $ Left err
        Right f  -> do
            (root, Assumptions unis merges apps accs) <- importFunction f
            mapM_ (reconnectLayer' @Requester newReq) merges
            mapM_ (reconnectLayer' @Requester newReq) unis
            mapM_ (reconnectLayer' @Requester newReq) apps
            mapM_ (reconnectLayer' @Requester newReq) accs
            modifyAttr_ @MergeQueue      $ wrapped %~ (merges ++)
            modifyAttr_ @Unifications    $ wrapped %~ (unis ++)
            modifyAttr_ @SimplifierQueue $ wrapped %~ (apps ++)
            modifyAttr_ @UnresolvedAccs  $ flip (foldr addAcc) accs
            return $ Right root

lookupClass :: Name -> Name -> Imports -> Either [CompileError] Class
lookupClass n clsN imps = case imps ^. importedClasses . at clsN of
    Nothing -> Left [CompileError (importErrorDoc n clsN) []]
    Just f  -> Right f

lookupMethod :: Name -> Name -> Class -> Either [CompileError] Function
lookupMethod n clsN cls = case Map.lookup n (cls ^. methods) of
    Just e  -> e
    _       -> Left [CompileError (importErrorDoc n clsN) []]
