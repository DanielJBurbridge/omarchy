function batteryPercentage(device) {
  if (!device || !device.isPresent) return -1
  return Math.round(Number(device.percentage || 0) * 100)
}

// Read the battery's own state, not UPower.onBattery: a dock or charger that supplies less than
// the machine draws keeps onBattery false while the battery drains.
function isDischarging(device, dischargingState) {
  return !!(device && device.isPresent && device.state === dischargingState)
}

function shouldWarnLowBattery(device, dischargingState, threshold, alreadyNotified) {
  var level = batteryPercentage(device)
  if (level < 0) return { level: level, notify: false, notifiedLowBattery: !!alreadyNotified }

  var low = isDischarging(device, dischargingState) && level <= threshold
  return {
    level: level,
    notify: low && !alreadyNotified,
    notifiedLowBattery: level <= threshold && !!(alreadyNotified || low)
  }
}

function parseActiveProfile(text) {
  // Properties.Get returns a D-Bus variant wrapping the string. An empty or
  // malformed reply (daemon not running) reads as no active profile.
  try {
    var value = JSON.parse(text).data[0]
    return value.type === "s" ? value.data.trim() : ""
  } catch (e) {
    return ""
  }
}

function profileAfterRead(current, replyText, signalsAtStart, signalsNow) {
  // A change signal that arrived during the read is newer than its reply.
  return signalsAtStart === signalsNow ? parseActiveProfile(replyText) : current
}

if (typeof module !== "undefined") {
  module.exports = {
    batteryPercentage: batteryPercentage,
    isDischarging: isDischarging,
    shouldWarnLowBattery: shouldWarnLowBattery,
    parseActiveProfile: parseActiveProfile,
    profileAfterRead: profileAfterRead
  }
}
