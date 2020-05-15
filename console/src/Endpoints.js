import globals from './Globals';

const baseUrl = globals.dataApiUrl;

const hasuractlUrl = globals.migrateApiUrl;

const Endpoints = {
  getSchema: `${baseUrl}/v1/query`,
  serverConfig: `${baseUrl}/v1alpha1/config`,
  graphQLUrl: `${baseUrl}/v1/graphql`,
  schemaChange: `${baseUrl}/v1/query`,
  query: `${baseUrl}/v1/query`,
  rawSQL: `${baseUrl}/v1/query`,
  version: `${baseUrl}/v1/version`,
  updateCheck: 'https://releases.hasura.io/graphql-engine',
  hasuractlMigrate: `${hasuractlUrl}/apis/migrate`,
  hasuractlMetadata: `${hasuractlUrl}/apis/metadata`,
  hasuractlMigrateSettings: `${hasuractlUrl}/apis/migrate/settings`,
  telemetryServer: 'wss://telemetry.hasura.io/v1/ws',
};

const globalCookiePolicy = 'same-origin';

export default Endpoints;
export { globalCookiePolicy, baseUrl, hasuractlUrl };
