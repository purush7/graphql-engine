package commands

import (
	"fmt"
	"net/url"
	"runtime"
	"strings"

	"github.com/hasura/graphql-engine/cli"
	"github.com/hasura/graphql-engine/cli/metadata"
	"github.com/hasura/graphql-engine/cli/metadata/actions"
	"github.com/hasura/graphql-engine/cli/metadata/allowlist"
	"github.com/hasura/graphql-engine/cli/metadata/functions"
	"github.com/hasura/graphql-engine/cli/metadata/querycollections"
	"github.com/hasura/graphql-engine/cli/metadata/remoteschemas"
	"github.com/hasura/graphql-engine/cli/metadata/tables"
	metadataTypes "github.com/hasura/graphql-engine/cli/metadata/types"
	metadataVersion "github.com/hasura/graphql-engine/cli/metadata/version"
	"github.com/hasura/graphql-engine/cli/migrate"
	mig "github.com/hasura/graphql-engine/cli/migrate/cmd"
	"github.com/hasura/graphql-engine/cli/version"
	"github.com/pkg/errors"
	"github.com/spf13/cobra"

	// Initialize migration drivers
	_ "github.com/hasura/graphql-engine/cli/migrate/database/hasuradb"
	_ "github.com/hasura/graphql-engine/cli/migrate/source/file"
)

// NewMigrateCmd returns the migrate command
func NewMigrateCmd(ec *cli.ExecutionContext) *cobra.Command {
	migrateCmd := &cobra.Command{
		Use:          "migrate",
		Short:        "Manage migrations on the database",
		SilenceUsage: true,
	}
	migrateCmd.AddCommand(
		newMigrateApplyCmd(ec),
		newMigrateStatusCmd(ec),
		newMigrateCreateCmd(ec),
		newMigrateSquashCmd(ec),
	)
	return migrateCmd
}

func newMigrate(ec *cli.ExecutionContext, isCmd bool) (*migrate.Migrate, error) {
	dbURL := getDataPath(ec.Config.ServerConfig.ParsedEndpoint, getAdminSecretHeaderName(ec.Version), ec.Config.ServerConfig.AdminSecret)
	fileURL := getFilePath(ec.MigrationDir)
	t, err := migrate.New(fileURL.String(), dbURL.String(), isCmd, ec.Logger)
	if err != nil {
		return nil, errors.Wrap(err, "cannot create migrate instance")
	}
	// Set Plugins
	setMetadataPlugins(t)
	return t, nil
}

// ExecuteMigration runs the actual migration
func ExecuteMigration(cmd string, t *migrate.Migrate, stepOrVersion int64) error {
	var err error

	switch cmd {
	case "up":
		err = mig.UpCmd(t, stepOrVersion)
	case "down":
		err = mig.DownCmd(t, stepOrVersion)
	case "version":
		var direction string
		if stepOrVersion >= 0 {
			direction = "up"
		} else {
			direction = "down"
			stepOrVersion = -(stepOrVersion)
		}
		err = mig.GotoCmd(t, uint64(stepOrVersion), direction)
	default:
		err = fmt.Errorf("Invalid command")
	}

	return err
}

func executeStatus(t *migrate.Migrate) (*migrate.Status, error) {
	status, err := t.GetStatus()
	if err != nil {
		return nil, err
	}
	return status, nil
}

func getDataPath(nurl *url.URL, adminSecretHeader, adminSecretValue string) *url.URL {
	host := &url.URL{
		Scheme: "hasuradb",
		Host:   nurl.Host,
		Path:   nurl.Path,
	}
	q := nurl.Query()
	// Set sslmode in query
	switch scheme := nurl.Scheme; scheme {
	case "https":
		q.Set("sslmode", "enable")
	default:
		q.Set("sslmode", "disable")
	}
	if adminSecretValue != "" {
		q.Add("headers", fmt.Sprintf("%s:%s", adminSecretHeader, adminSecretValue))
	}
	host.RawQuery = q.Encode()
	return host
}

func getFilePath(dir string) *url.URL {
	host := &url.URL{
		Scheme: "file",
		Path:   dir,
	}

	// Add Prefix / to path if runtime.GOOS equals to windows
	if runtime.GOOS == "windows" && !strings.HasPrefix(host.Path, "/") {
		host.Path = "/" + host.Path
	}
	return host
}

const (
	XHasuraAdminSecret = "X-Hasura-Admin-Secret"
	XHasuraAccessKey   = "X-Hasura-Access-Key"
)

func getAdminSecretHeaderName(v *version.Version) string {
	if v.ServerSemver == nil {
		return XHasuraAdminSecret
	}
	flags, err := v.GetServerFeatureFlags()
	if err != nil {
		return XHasuraAdminSecret
	}
	if flags.HasAccessKey {
		return XHasuraAccessKey
	}
	return XHasuraAdminSecret
}

// dir is optional
func setMetadataPlugins(drv *migrate.Migrate, dir ...string) {
	var metadataDir string
	if len(dir) == 0 {
		metadataDir = ec.MetadataDir
	} else {
		metadataDir = dir[0]
	}
	plugins := metadataTypes.MetadataPlugins{}
	if ec.Config.Version == "2" && metadataDir != "" {
		plugins["version"] = metadataVersion.New(ec, metadataDir)
		plugins["tables"] = tables.New(ec, metadataDir)
		plugins["functions"] = functions.New(ec, metadataDir)
		plugins["query_collections"] = querycollections.New(ec, metadataDir)
		plugins["allow_list"] = allowlist.New(ec, metadataDir)
		plugins["remote_schemas"] = remoteschemas.New(ec, metadataDir)
		plugins["actions"] = actions.New(ec, metadataDir)
	} else {
		plugins["metadata"] = metadata.New(ec, ec.MigrationDir)
	}
	drv.SetMetadataPlugins(plugins)
}
