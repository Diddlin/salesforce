const { jestConfig } = require("@salesforce/sfdx-lwc-jest/config");

module.exports = {
  ...jestConfig,
  modulePathIgnorePatterns: ["<rootDir>/.localdevserver"],
  moduleNameMapper: {
    ...jestConfig.moduleNameMapper,
    // sfdx-lwc-jest ships no stub for lightning/modal yet.
    "^lightning/modal$": "<rootDir>/force-app/test/jest-mocks/lightning/modal"
  }
};
