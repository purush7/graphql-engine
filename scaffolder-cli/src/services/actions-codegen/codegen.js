const fetch = require('node-fetch');
const { getTemplatePath } = require('../../utils/utils');
const { parseCustomTypes, getActionTypes } = require('../../shared/utils/hasuraCustomTypeUtils')
const { getFrameworkCodegen } = require('./template');
const { getActionDefinitionSdl, getTypesSdl } = require('../../shared/utils/sdlUtils');
const { parse: sdlParse } = require('graphql/language/parser');

const getActionsCodegen = async (payload) => {

  const {
    action_name: actionName,
    sdl: {
      complete: sdlComplete
    },
    derive,
    actions_config: actionsConfig
  } = payload;

  try {
    const codegenResp = await getFrameworkCodegen(actionName, sdlComplete, derive, actionsConfig.codegen)
    if (codegenResp.error) {
      throw Error(codegenResp.error)
    } else {
      return codegenResp.files
    }
  } catch (e) {
    throw e;
  }
};

module.exports = {
  getActionsCodegen 
};

