import { unwrapType } from './wrappingTypeUtils';

const singularize = kind => {
  return kind.substr(0, kind.length - 1);
};

export const filterNameLessTypeLess = arr => {
  return arr.filter(item => !!item.name && !!item.type);
};

export const filterNameless = arr => {
  return arr.filter(item => !!item.name);
};

export const filterValueLess = arr => {
  return arr.filter(item => !!item.value);
};

export const mergeCustomTypes = (newTypesList, existingTypesList) => {
  let mergedTypes = [];
  let overlappingTypename = null;
  const modifiedTypeIndices = [];
  newTypesList.forEach(nt => {
    const modifiedTypeIndex = existingTypesList.findIndex(
      et => et.name === nt.name
    );
    if (modifiedTypeIndex !== -1) {
      if (!nt.isModifying) {
        overlappingTypename = nt.name;
      } else {
        modifiedTypeIndices.push(modifiedTypeIndex);
      }
    }
    mergedTypes.push(nt);
  });
  mergedTypes = [
    ...mergedTypes,
    ...existingTypesList.filter(
      (t, i) => !modifiedTypeIndices.find(mti => i === mti)
    ),
  ];
  return {
    types: mergedTypes,
    overlappingTypename,
  };
};

export const reformCustomTypes = typesFromState => {
  const sanitisedTypes = [];
  typesFromState.forEach(t => {
    if (!t.name) {
      return;
    }
    const sanitisedType = { ...t };
    if (t.fields) {
      sanitisedType.fields = filterNameLessTypeLess(t.fields);
    }
    if (t.arguments) {
      sanitisedType.arguments = filterNameLessTypeLess(t.arguments);
    }

    sanitisedTypes.push(sanitisedType);
  });

  const customTypes = {
    scalars: [],
    input_objects: [],
    objects: [],
    enums: [],
  };

  sanitisedTypes.forEach(_type => {
    const type = JSON.parse(JSON.stringify(_type));
    delete type.kind;
    switch (_type.kind) {
      case 'scalar':
        customTypes.scalars.push(type);
        return;
      case 'object':
        customTypes.objects.push(type);
        return;
      case 'input_object':
        customTypes.input_objects.push(type);
        return;
      case 'enum':
        customTypes.enums.push(type);
        return;
      default:
        return;
    }
  });

  return customTypes;
};

export const parseCustomTypes = customTypesServer => {
  const customTypesClient = [];
  Object.keys(customTypesServer).forEach(tk => {
    const types = customTypesServer[tk];
    types.forEach(t => {
      customTypesClient.push({
        ...t,
        kind: singularize(tk),
      });
    });
  });
  return customTypesClient;
};

export const getActionTypes = (actionDef, allTypes) => {
  const usedTypes = {};
  const actionTypes = [];
  const getDependentTypes = typename => {
    if (usedTypes[typename]) return;
    const type = allTypes.find(t => t.name === typename);
    if (!type) return;
    actionTypes.push(type);
    usedTypes[typename] = true;
    if (type.kind === 'input_object' || type.kind === 'object') {
      type.fields.forEach(f => {
        const { typename: _typename } = unwrapType(f.type);
        getDependentTypes(_typename);
      });
    }
  };

  actionDef.arguments.forEach(a => {
    const { typename } = unwrapType(a.type);
    getDependentTypes(typename);
  });

  getDependentTypes(actionDef.output_type);
  console.log(actionTypes);
  return actionTypes;
};