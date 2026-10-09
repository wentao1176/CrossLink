const appVersion = '0.3.0';
const isQa = String.fromEnvironment('CROSSLINK_BUILD_CHANNEL') == 'qa';
const sessionStorageKey = isQa ? 'crosslink_qa_session' : 'crosslink_session';
const appName = isQa ? 'CrossLink QA' : 'CrossLink';
