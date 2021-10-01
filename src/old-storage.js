const localforage = require("localforage");

import {
  promisified
} from "tauri/api/tauri";

if (!window.__TAURI__) {
  localforage.config({
    driver: localforage.INDEXEDDB, // Force WebSQL; same as using setDriver()
    name: "zeitplan",
    version: 1.0,
    size: 4980736, // Size of database, in bytes. WebSQL-only for now.
    storeName: "zeitplan_key_value_pairs", // Should be alphanumeric, with underscores.
    description: "storage used for users, meetings, and events",
  })
}

function serializeTauri(data) {
  if (data instanceof Map) {
    let ret = {};
    for (let [key, value] of data.entries()) {
      ret[key] = value;
    }
    return ret;
  } else {
    return data;
  }
}

function setKey(key, value) {
  if (window.__TAURI__) {
    value = serializeTauri(value);
    // we need to transform Map objects to objects.
    return promisified({
      cmd: "setKey",
      payload: {
        key,
        value: JSON.stringify(value),
      },
    });
  } else {
    return localforage.setItem(key, value);
  }
}

function getKey(key) {
  if (window.__TAURI__) {
    return promisified({
      cmd: "getKey",
      payload: key,
    }).then((d) => {
      try {
        return JSON.parse(d);
      } catch (e) {
        return null;
      }
    });
  } else {
    console.log(key);
    return localforage.getItem(key);
  }
}

function deleteKey(key) {
  if (window.__TAURI__) {
    return promisified({
      cmd: "deleteKey",
      payload: key,
    });
  } else {
    return localforage.removeItem(key);
  }
}

export {
  setKey,
  getKey,
  deleteKey
};
