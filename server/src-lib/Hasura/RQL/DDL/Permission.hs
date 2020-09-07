module Hasura.RQL.DDL.Permission
    ( CreatePerm
    , runCreatePerm
    -- , purgePerm
    , PermDef(..)

    , InsPerm(..)
    , InsPermDef
    , CreateInsPerm
    , buildInsPermInfo

    , SelPerm(..)
    , SelPermDef
    , CreateSelPerm
    , buildSelPermInfo

    , UpdPerm(..)
    , UpdPermDef
    , CreateUpdPerm
    , buildUpdPermInfo

    , DelPerm(..)
    , DelPermDef
    , CreateDelPerm
    , buildDelPermInfo

    , IsPerm(..)
    , addPermP2

    , DropPerm
    , runDropPerm
    , dropPermissionInMetadata

    , SetPermComment(..)
    , runSetPermComment

    , fetchPermDef
    ) where

import           Hasura.EncJSON
import           Hasura.Incremental                 (Cacheable)
import           Hasura.Prelude
import           Hasura.RQL.DDL.Permission.Internal
import           Hasura.RQL.DML.Internal            hiding (askPermInfo)
import           Hasura.RQL.Types
import           Hasura.Session
import           Hasura.SQL.Types

import qualified Database.PG.Query                  as Q

import           Data.Aeson
import           Data.Aeson.Casing
import           Data.Aeson.TH
import           Language.Haskell.TH.Syntax         (Lift)

import qualified Data.HashMap.Strict                as HM
import qualified Data.HashSet                       as HS
import qualified Data.Text                          as T

{- Note [Backend only permissions]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
As of writing this note, Hasura permission system is meant to be used by the
frontend. After introducing "Actions", the webhook handlers now can make GraphQL
mutations to the server with some backend logic. These mutations shouldn't be
exposed to frontend for any user since they'll bypass the business logic.

For example:-

We've a table named "user" and it has a "email" column. We need to validate the
email address. So we define an action "create_user" and it expects the same inputs
as "insert_user" mutation (generated by Hasura). Now, a role has permission for both
actions and insert operation on the table. If the insert permission is not marked
as "backend_only: true" then it visible to the frontend client along with "creat_user".

Backend only permissions adds an additional privilege to Hasura generated operations.
Those are accessable only if the request is made with `x-hasura-admin-secret`
(if authorization is configured), `x-hasura-use-backend-only-permissions`
(value must be set to "true"), `x-hasura-role` to identify the role and other
required session variables.

backend_only   `x-hasura-admin-secret`   `x-hasura-use-backend-only-permissions`  Result
------------    ---------------------     -------------------------------------   ------
FALSE           ANY                       ANY                                    Mutation is always visible
TRUE            FALSE                     ANY                                    Mutation is always hidden
TRUE            TRUE (OR NOT-SET)         FALSE                                  Mutation is hidden
TRUE            TRUE (OR NOT-SET)         TRUE                                   Mutation is shown
-}

type CreateInsPerm = CreatePerm InsPerm

procSetObj
  :: (QErrM m)
  => QualifiedTable
  -> FieldInfoMap FieldInfo
  -> Maybe (ColumnValues Value)
  -> m (PreSetColsPartial, [Text], [SchemaDependency])
procSetObj tn fieldInfoMap mObj = do
  (setColTups, deps) <- withPathK "set" $
    fmap unzip $ forM (HM.toList setObj) $ \(pgCol, val) -> do
      ty <- askPGType fieldInfoMap pgCol $
        "column " <> pgCol <<> " not found in table " <>> tn
      sqlExp <- valueParser (PGTypeScalar ty) val
      let dep = mkColDep (getDepReason sqlExp) tn pgCol
      return ((pgCol, sqlExp), dep)
  return (HM.fromList setColTups, depHeaders, deps)
  where
    setObj = fromMaybe mempty mObj
    depHeaders = getDepHeadersFromVal $ Object $
      HM.fromList $ map (first getPGColTxt) $ HM.toList setObj

    getDepReason = bool DRSessionVariable DROnType . isStaticValue

buildInsPermInfo
  :: (QErrM m, TableCoreInfoRM m)
  => QualifiedTable
  -> FieldInfoMap FieldInfo
  -> PermDef InsPerm
  -> m (WithDeps InsPermInfo)
buildInsPermInfo tn fieldInfoMap (PermDef _rn (InsPerm checkCond set mCols mBackendOnly) _) =
  withPathK "permission" $ do
    (be, beDeps) <- withPathK "check" $ procBoolExp tn fieldInfoMap checkCond
    (setColsSQL, setHdrs, setColDeps) <- procSetObj tn fieldInfoMap set
    void $ withPathK "columns" $ indexedForM insCols $ \col ->
           askPGType fieldInfoMap col ""
    let fltrHeaders = getDependentHeaders checkCond
        reqHdrs = fltrHeaders `union` setHdrs
        insColDeps = map (mkColDep DRUntyped tn) insCols
        deps = mkParentDep tn : beDeps ++ setColDeps ++ insColDeps
        insColsWithoutPresets = insCols \\ HM.keys setColsSQL
    return (InsPermInfo (HS.fromList insColsWithoutPresets) be setColsSQL backendOnly reqHdrs, deps)
  where
    backendOnly = fromMaybe False mBackendOnly
    allCols = map pgiColumn $ getCols fieldInfoMap
    insCols = fromMaybe allCols $ convColSpec fieldInfoMap <$> mCols

type instance PermInfo InsPerm = InsPermInfo

instance IsPerm InsPerm where

  permAccessor = PAInsert

  buildPermInfo = buildInsPermInfo

  addPermToMetadata permDef =
    tmInsertPermissions %~ HM.insert (_pdRole permDef) permDef

buildSelPermInfo
  :: (QErrM m, TableCoreInfoRM m)
  => QualifiedTable
  -> FieldInfoMap FieldInfo
  -> SelPerm
  -> m (WithDeps SelPermInfo)
buildSelPermInfo tn fieldInfoMap sp = withPathK "permission" $ do
  let pgCols     = convColSpec fieldInfoMap $ spColumns sp

  (be, beDeps) <- withPathK "filter" $
    procBoolExp tn fieldInfoMap  $ spFilter sp

  -- check if the columns exist
  void $ withPathK "columns" $ indexedForM pgCols $ \pgCol ->
    askPGType fieldInfoMap pgCol autoInferredErr

  -- validate computed fields
  scalarComputedFields <-
    withPathK "computed_fields" $ indexedForM computedFields $ \fieldName -> do
      computedFieldInfo <- askComputedFieldInfo fieldInfoMap fieldName
      case _cfiReturnType computedFieldInfo of
        CFRScalar _               -> pure fieldName
        CFRSetofTable returnTable -> throw400 NotSupported $
          "select permissions on computed field " <> fieldName
          <<> " are auto-derived from the permissions on its returning table "
          <> returnTable <<> " and cannot be specified manually"

  let deps = mkParentDep tn : beDeps ++ map (mkColDep DRUntyped tn) pgCols
             ++ map (mkComputedFieldDep DRUntyped tn) scalarComputedFields
      depHeaders = getDependentHeaders $ spFilter sp
      mLimit = spLimit sp

  withPathK "limit" $ mapM_ onlyPositiveInt mLimit

  return ( SelPermInfo (HS.fromList pgCols) (HS.fromList computedFields)
                        be mLimit allowAgg depHeaders
         , deps
         )
  where
    allowAgg = spAllowAggregations sp
    computedFields = spComputedFields sp
    autoInferredErr = "permissions for relationships are automatically inferred"

type CreateSelPerm = CreatePerm SelPerm

type instance PermInfo SelPerm = SelPermInfo

instance IsPerm SelPerm where

  permAccessor = PASelect

  buildPermInfo tn fieldInfoMap (PermDef _ a _) =
    buildSelPermInfo tn fieldInfoMap a

  addPermToMetadata permDef =
    tmSelectPermissions %~ HM.insert (_pdRole permDef) permDef

type CreateUpdPerm = CreatePerm UpdPerm

buildUpdPermInfo
  :: (QErrM m, TableCoreInfoRM m)
  => QualifiedTable
  -> FieldInfoMap FieldInfo
  -> UpdPerm
  -> m (WithDeps UpdPermInfo)
buildUpdPermInfo tn fieldInfoMap (UpdPerm colSpec set fltr check) = do
  (be, beDeps) <- withPathK "filter" $
    procBoolExp tn fieldInfoMap fltr

  checkExpr <- traverse (withPathK "check" . procBoolExp tn fieldInfoMap) check

  (setColsSQL, setHeaders, setColDeps) <- procSetObj tn fieldInfoMap set

  -- check if the columns exist
  void $ withPathK "columns" $ indexedForM updCols $ \updCol ->
       askPGType fieldInfoMap updCol relInUpdErr

  let updColDeps = map (mkColDep DRUntyped tn) updCols
      deps = mkParentDep tn : beDeps ++ maybe [] snd checkExpr ++ updColDeps ++ setColDeps
      depHeaders = getDependentHeaders fltr
      reqHeaders = depHeaders `union` setHeaders
      updColsWithoutPreSets = updCols \\ HM.keys setColsSQL

  return (UpdPermInfo (HS.fromList updColsWithoutPreSets) tn be (fst <$> checkExpr) setColsSQL reqHeaders, deps)

  where
    updCols     = convColSpec fieldInfoMap colSpec
    relInUpdErr = "relationships can't be used in update"

type instance PermInfo UpdPerm = UpdPermInfo

instance IsPerm UpdPerm where

  permAccessor = PAUpdate

  buildPermInfo tn fieldInfoMap (PermDef _ a _) =
    buildUpdPermInfo tn fieldInfoMap a

  addPermToMetadata permDef =
    tmUpdatePermissions %~ HM.insert (_pdRole permDef) permDef

type CreateDelPerm = CreatePerm DelPerm

buildDelPermInfo
  :: (QErrM m, TableCoreInfoRM m)
  => QualifiedTable
  -> FieldInfoMap FieldInfo
  -> DelPerm
  -> m (WithDeps DelPermInfo)
buildDelPermInfo tn fieldInfoMap (DelPerm fltr) = do
  (be, beDeps) <- withPathK "filter" $
    procBoolExp tn fieldInfoMap  fltr
  let deps = mkParentDep tn : beDeps
      depHeaders = getDependentHeaders fltr
  return (DelPermInfo tn be depHeaders, deps)

type instance PermInfo DelPerm = DelPermInfo

instance IsPerm DelPerm where

  permAccessor = PADelete

  buildPermInfo tn fieldInfoMap (PermDef _ a _) =
    buildDelPermInfo tn fieldInfoMap a

  addPermToMetadata permDef =
    tmDeletePermissions %~ HM.insert (_pdRole permDef) permDef

data SetPermComment
  = SetPermComment
  { apSource     :: !SourceName
  , apTable      :: !QualifiedTable
  , apRole       :: !RoleName
  , apPermission :: !PermType
  , apComment    :: !(Maybe T.Text)
  } deriving (Show, Eq, Lift)

$(deriveJSON (aesonDrop 2 snakeCase) ''SetPermComment)

setPermCommentP1 :: (UserInfoM m, QErrM m, CacheRM m) => SetPermComment -> m ()
setPermCommentP1 (SetPermComment sourceName qt rn pt _) = do
  tabInfo <- askTabInfo sourceName qt
  action tabInfo
  where
    action tabInfo = case pt of
      PTInsert -> assertPermDefined rn PAInsert tabInfo
      PTSelect -> assertPermDefined rn PASelect tabInfo
      PTUpdate -> assertPermDefined rn PAUpdate tabInfo
      PTDelete -> assertPermDefined rn PADelete tabInfo

setPermCommentP2 :: (QErrM m, MonadTx m) => SetPermComment -> m EncJSON
setPermCommentP2 apc = do
  liftTx $ setPermCommentTx apc
  return successMsg

runSetPermComment
  :: (QErrM m, CacheRM m, MonadTx m, UserInfoM m)
  => SetPermComment -> m EncJSON
runSetPermComment defn =  do
  setPermCommentP1 defn
  setPermCommentP2 defn

setPermCommentTx
  :: SetPermComment
  -> Q.TxE QErr ()
setPermCommentTx (SetPermComment sourceName (QualifiedObject sn tn) rn pt comment) =
  Q.unitQE defaultTxErrorHandler [Q.sql|
           UPDATE hdb_catalog.hdb_permission
           SET comment = $1
           WHERE table_schema =  $2
             AND table_name = $3
             AND role_name = $4
             AND perm_type = $5
                |] (comment, sn, tn, rn, permTypeToCode pt) True

-- purgePerm :: MonadTx m => SourceName -> QualifiedTable -> RoleName -> PermType -> m ()
-- purgePerm sourceName qt rn pt =
--     case pt of
--       PTInsert -> dropPermP2 @InsPerm dp
--       PTSelect -> dropPermP2 @SelPerm dp
--       PTUpdate -> dropPermP2 @UpdPerm dp
--       PTDelete -> dropPermP2 @DelPerm dp
--   where
--     dp :: DropPerm a
--     dp = DropPerm sourceName qt rn

fetchPermDef
  :: QualifiedTable
  -> RoleName
  -> PermType
  -> Q.TxE QErr (Value, Maybe T.Text)
fetchPermDef (QualifiedObject sn tn) rn pt =
 (first Q.getAltJ .  Q.getRow) <$> Q.withQE defaultTxErrorHandler
      [Q.sql|
            SELECT perm_def::json, comment
              FROM hdb_catalog.hdb_permission
             WHERE table_schema = $1
               AND table_name = $2
               AND role_name = $3
               AND perm_type = $4
            |] (sn, tn, rn, permTypeToCode pt) True
