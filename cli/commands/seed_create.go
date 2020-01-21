package commands

import (
	"github.com/hasura/graphql-engine/cli"
	"github.com/hasura/graphql-engine/cli/seed"
	"github.com/pkg/errors"
	"github.com/skratchdot/open-golang/open"
	"github.com/spf13/cobra"
)

type seedNewOptions struct {
	ec *cli.ExecutionContext

	// filename for the new seed file
	seedname string
}

func newSeedCreateCmd(ec *cli.ExecutionContext) *cobra.Command {
	opts := seedNewOptions{
		ec: ec,
	}
	cmd := &cobra.Command{
		Use:          "create",
		Short:        "create a new seed file",
		SilenceUsage: false,
		RunE: func(cmd *cobra.Command, args []string) error {
			opts.seedname = args[0]
			return opts.run()
		},
		Args: cobra.ExactArgs(1),
	}

	return cmd
}

func (o *seedNewOptions) run() error {
	createSeedOpts := seed.CreateSeedOptions{
		UserProvidedSeedName: o.seedname,
	}
	filepath, err := seed.CreateSeed(createSeedOpts)
	if err != nil || filepath == nil {
		return errors.Wrap(err, "failed to create seed file")
	}
	// Open file in default editor
	open.Run(*filepath)
	return nil
}
