import { isWrappingType, isListType, isNonNullType } from 'graphql';

const wrapNonNullable = typename => {
  return `${typename}!`;
};

const wrapList = typename => {
  return `[${typename}]`;
};

const wrapNullableListOfNonNullable = typename => {
  return `[${typename}!]`;
};

const wrapNonNullableListOfNullable = typename => {
  return `[${typename}]!`;
};

const wrapNonNullableListOfNonNullable = typename => {
  return `[${typename}!]!`;
};

export const isNonNullable = wrappedTypename => {
  return wrappedTypename[wrappedTypename.length - 1] === '!';
};

export const isList = wrappedTypename => {
  return wrappedTypename[wrappedTypename.length - 1] === ']';
};

const unwrapNonNullable = wrappedTypename => {
  return wrappedTypename.substring(0, wrappedTypename.length - 1);
};

const unwrapList = wrappedTypename => {
  return wrappedTypename.substring(1, wrappedTypename.length - 1);
};

export const typeWrappers = [
  {
    label: 'Nullable',
    wrapperFunc: typename => typename,
  },
  {
    label: 'Non-nullable',
    wrapperFunc: wrapNonNullable,
  },
  {
    label: 'Nullable list of nullable',
    wrapperFunc: wrapList,
  },
  {
    label: 'Nullable list of non-nullable',
    wrapperFunc: wrapNullableListOfNonNullable,
  },
  {
    label: 'Non-nullable list of nullable',
    wrapperFunc: wrapNonNullableListOfNullable,
  },
  {
    label: 'Non-nullable list of non-nullable',
    wrapperFunc: wrapNonNullableListOfNonNullable,
  },
];

export const unwrapType = wrappedTypename => {
  let _typename = wrappedTypename;
  const typeWrapperStack = [];

  while (true) {
    const _lastChar = _typename.charAt(_typename.length - 1);
    if (_lastChar === ']') {
      _typename = unwrapList(_typename);
      typeWrapperStack.push('l');
      continue;
    }
    if (_lastChar === '!') {
      _typename = unwrapNonNullable(_typename);
      typeWrapperStack.push('n');
      continue;
    }

    break;
  }

  return {
    stack: typeWrapperStack,
    typename: _typename,
  };
};

export const getUnderlyingType = graphqlType => {
  let _type = graphqlType;
  while (isWrappingType(_type)) {
    _type = _type.ofType;
  }
  return _type;
};

export const getAstTypeMetadata = type => {
  let _t = { type };
  const typewraps = [];
  while (_t.kind !== 'NamedType') {
    if (_t.kind === 'ListType') {
      typewraps.push('l');
    }
    if (_t.kind === 'NonNullType') {
      typewraps.push('n');
    }
    _t = _t.type;
  }
  const typename = _t.name.value;
  return {
    typename,
    stack: typewraps,
  };
};

export const getSchemaTypeMetadata = type => {
  let _t = type;
  const typewraps = [];
  while (isWrappingType(_t)) {
    if (isListType(_t)) {
      typewraps.push('l');
    }
    if (isNonNullType(_t)) {
      typewraps.push('n');
    }
    _t = _t.ofType;
  }

  return {
    typename: _t.name,
    stack: typewraps,
  };
};

export const wrapTypename = (name, wrapperStack) => {
  let wrappedTypename = name;
  wrapperStack.forEach(w => {
    if (w === 'l') {
      wrappedTypename = `[${wrappedTypename}]`;
    }
    if (w === 'n') {
      wrappedTypename = `${wrappedTypename}!`;
    }
  });
  return wrappedTypename;
};