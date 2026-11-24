const assert = require("node:assert/strict")
const test = require("node:test")
const { addAbiConfigToBuildGradle, updateGradleProperties } = require("./withAbiSupport")

const TEMPLATE_GRADLE = `apply plugin: "com.android.application"
android {
    ndkVersion rootProject.ext.ndkVersion
    namespace 'cc.agentlabs.opencode'
    defaultConfig {
        applicationId 'cc.agentlabs.opencode'
        versionCode 54
        versionName "0.4.27"
    }
}
`

const TEMPLATE_PROPERTIES = `org.gradle.jvmargs=-Xmx2048m -XX:MaxMetaspaceSize=512m
org.gradle.parallel=true
android.useAndroidX=true
reactNativeArchitectures=armeabi-v7a,arm64-v8a,x86,x86_64
`

test("injects ABI filters and idempotent splits into a prebuild template", () => {
  const result = addAbiConfigToBuildGradle(TEMPLATE_GRADLE)
  assert.match(result, /def enabledAbis/)
  assert.match(result, /abiFilters\(\*enabledAbis\)/)
  assert.match(result, /include\(\*enabledAbis\)/)
  assert.match(result, /universalApk true/)
  assert.equal(addAbiConfigToBuildGradle(result), result)
})

test("does not duplicate ABI config when it is already present", () => {
  const result = addAbiConfigToBuildGradle(addAbiConfigToBuildGradle(TEMPLATE_GRADLE))
  assert.equal((result.match(/def enabledAbis/g) || []).length, 1)
  assert.equal((result.match(/abiFilters\(/g) || []).length, 1)
})

test("rewrites architecture and Gradle memory properties idempotently", () => {
  const result = updateGradleProperties(TEMPLATE_PROPERTIES)
  assert.match(result, /^reactNativeArchitectures=armeabi-v7a,arm64-v8a$/m)
  assert.match(result, /^org\.gradle\.jvmargs=-Xmx4096m/m)
  assert.match(result, /^org\.gradle\.workers\.max=2$/m)
  assert.match(result, /^android\.useAndroidX=true$/m)
  assert.equal(updateGradleProperties(result), result)
})
