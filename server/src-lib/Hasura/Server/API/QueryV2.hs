-- | The RQL metadata query ('/v2/query')
module Hasura.Server.API.QueryV2 where

import           Hasura.EncJSON
import           Hasura.Prelude
import           Hasura.RQL.DDL.Schema
import           Hasura.RQL.DML.Count
import           Hasura.RQL.DML.Delete
import           Hasura.RQL.DML.Insert
import           Hasura.RQL.DML.Select
import           Hasura.RQL.DML.Update
import           Hasura.RQL.Types
import           Hasura.RQL.Types.Run
import           Hasura.Server.Version (HasVersion)
import           Hasura.Session
import           Hasura.SQL.Types

import qualified Hasura.Tracing        as Tracing

import           Control.Lens          (makePrisms, (^?))
import           Control.Monad.Morph   (hoist)
import           Data.Aeson
import           Data.Aeson.Casing
import           Data.Aeson.TH

import qualified Data.Environment      as Env
import qualified Data.HashMap.Strict   as M
import qualified Database.PG.Query     as Q
import qualified Network.HTTP.Client   as HTTP

data RQLQuery
  = RQInsert !InsertQuery
  | RQSelect !SelectQuery
  | RQUpdate !UpdateQuery
  | RQDelete !DeleteQuery
  | RQCount  !CountQuery

  | RQRunSql !RunSQL

$(deriveJSON
  defaultOptions { constructorTagModifier = snakeCase . drop 2
                 , sumEncoding = TaggedObject "type" "args"
                 }
  ''RQLQuery)
$(makePrisms ''RQLQuery)

data QueryWithSource
  = QueryWithSource
    { _wsSource :: !SourceName
    , _wsQuery  :: !RQLQuery
    }

instance FromJSON QueryWithSource where
  parseJSON = withObject "Object" $ \o -> do
    source <- o .:? "source" .!= defaultSource
    rqlQuery <- parseJSON $ Object o
    pure $ QueryWithSource source rqlQuery

instance ToJSON QueryWithSource where
  toJSON (QueryWithSource source rqlQuery) =
    case toJSON rqlQuery of
      Object o -> Object $ M.insert "source" (toJSON source) o
      -- never happens since JSON value of RQL queries are always objects
      _        -> error "Unexpected: toJSON of RQL queries are not objects"

runQuery
  :: ( HasVersion
     , MonadIO m
     , MonadError QErr m
     , Tracing.MonadTrace m
     )
  => Env.Environment
  -> UserInfo
  -> HTTP.Manager
  -> SQLGenCtx
  -> PGSourceConfig
  -> RebuildableSchemaCache MetadataRun
  -> Metadata
  -> QueryWithSource
  -> m EncJSON
runQuery env userInfo httpManager sqlGenCtx defSourceConfig schemaCache metadata request = do
  traceCtx <- Tracing.currentContext
  let accessMode = fromMaybe Q.ReadWrite $ rqlQuery ^? _RQRunSql.rTxAccessMode
      sc = lastBuiltSchemaCache schemaCache
  sourceConfig <- fmap _pcConfiguration $ onNothing (M.lookup source (scPostgres sc)) $
                  throw400 NotExists $ "source " <> source <<> " does not exist"
  runQueryM env source rqlQuery & Tracing.interpTraceT \x -> do
    a <- x & runCacheRWT schemaCache
           -- & liftQueryToMetadataRun traceCtx sourceConfig accessMode
           & peelRun (RunCtx userInfo httpManager sqlGenCtx defSourceConfig) metadata
           & runExceptT
    liftEither a <&> \(((r, tracemeta), _, _), _) -> (r, tracemeta)
  where
    QueryWithSource source rqlQuery = request

runQueryM
  :: ( HasVersion
     , MonadIO m
     , UserInfoM m
     , CacheRWM m
     , MonadTx m
     , HasSQLGenCtx m
     , Tracing.MonadTrace m
     )
  => Env.Environment -> SourceName -> RQLQuery -> m EncJSON
runQueryM env source = \case
  RQInsert q -> runInsert env source q
  RQSelect q -> runSelect source q
  RQUpdate q -> runUpdate env source q
  RQDelete q -> runDelete env source q
  RQCount  q -> runCount source q
  RQRunSql q -> runRunSQL q