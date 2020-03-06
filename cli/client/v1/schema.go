package v1

import (
	"encoding/json"
	"net/http"

	"github.com/parnurzeal/gorequest"
)

// SendQuery does what the name implies
func (client *Client) SendQuery(m interface{}) (*http.Response, []byte, *Error) {
	request := gorequest.New()
	request = request.Post(client.SchemaMetadataAPIEndpoint.String()).Send(m)

	for headerName, headerValue := range client.Headers {
		request.Set(headerName, headerValue)
	}

	resp, body, errs := request.EndBytes()
	if len(errs) != 0 {
		return resp, body, E(errs[0])
	}

	if resp.StatusCode != http.StatusOK {
		var apiError APIError
		err := json.Unmarshal(body, &apiError)
		if err != nil {
			return nil, nil, E(err)
		}
		return nil, nil, E(apiError)
	}
	return resp, body, nil
}