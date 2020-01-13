package commands

import (
	"fmt"

	"github.com/hasura/graphql-engine/cli"
	"github.com/hasura/graphql-engine/cli/metadata/actions"
	"github.com/spf13/cobra"
	"github.com/spf13/viper"
)

func newActionsCodegenCmd(ec *cli.ExecutionContext) *cobra.Command {
	v := viper.New()
	opts := &actionsCodegenOptions{
		EC: ec,
	}
	actionsCodegenCmd := &cobra.Command{
		Use:               "codegen",
		Short:             "",
		SilenceUsage:      true,
		PersistentPreRunE: ensureCLIExtension,
		PreRunE: func(cmd *cobra.Command, args []string) error {
			ec.Viper = v
			err := ec.Validate()
			if err != nil {
				return err
			}
			if ec.MetadataDir == "" {
				return fmt.Errorf("actions commands can be executed only when metadata_dir is set in config")
			}
			return nil
		},
		RunE: func(cmd *cobra.Command, args []string) error {
			opts.actions = args
			return opts.run()
		},
	}

	return actionsCodegenCmd
}

type actionsCodegenOptions struct {
	EC *cli.ExecutionContext
	actions []string
}

func (o *actionsCodegenOptions) run() (err error) {

	actionCfg := actions.New(o.EC.MetadataDir, o.EC.Config.Action, o.EC.CMDName)
	var derivePayload actions.DerivePayload

	// if no actions are passed, perform codegen for all actions
	var codegenActions []string
	if len(o.actions) == 0 {
		actionsFileContent, err := actions.GetActionsFileContent(o.EC.MetadataDir)
		if err != nil {
			return err
		}
		for _, action := range actionsFileContent.Actions {
			codegenActions = append(codegenActions, action.Name)
		}
	} else {
		codegenActions = o.actions			
	}

	for _, actionName := range codegenActions {
		err = actionCfg.Codegen(actionName, derivePayload)
		if err != nil {
			return err
		}
	}

	return nil

}