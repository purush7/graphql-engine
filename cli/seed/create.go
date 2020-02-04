package seed

import (
	"fmt"
	"path/filepath"
	"strconv"
	"time"

	"github.com/spf13/afero"
)

// CreateSeedOptions has the list of options required
// to create a seed file
type CreateSeedOptions struct {
	UserProvidedSeedName string
	// DirectoryPath in which seed file should be created
	DirectoryPath string
}

// CreateSeedFile creates a .sql file according to the arguments
// it'll return full filepath and an error if any
func CreateSeedFile(fs afero.Fs, opts CreateSeedOptions) (*string, error) {
	const fileExtension = "sql"

	timestamp := strconv.FormatInt(time.Now().UnixNano()/int64(time.Millisecond), 10)
	// filename will be in format <timestamp>_<userProvidedSeedName>.sql
	filenameWithTimeStamp := fmt.Sprintf("%s_%s.%s", timestamp, opts.UserProvidedSeedName, fileExtension)
	fullFilePath := filepath.Join(opts.DirectoryPath, filenameWithTimeStamp)

	// Create file
	file, err := fs.Create(fullFilePath)
	if err != nil {
		return nil, err
	}
	defer file.Close()
	return &fullFilePath, nil
}