group = "com.rwfit.rwfit_ble"
version = "1.0-SNAPSHOT"

buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath("com.android.tools.build:gradle:8.1.0")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
        maven { url = uri("${project.projectDir}/repo") }
    }
}

plugins {
    id("com.android.library")
}

android {
    namespace = "com.rwfit.rwfit_ble"

    compileSdk = 35

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }

    sourceSets {
        getByName("main") {
            java.srcDirs("src/main/java")
        }
    }

    defaultConfig {
        minSdk = 26
    }
}

dependencies {
    // RW 戒指原生 SDK（通过本地 maven repo 引用）
    implementation("com.rwfit:blesdk-rwfit:1.0")
    // FastJSON：现有桥接层用它构造 SDK 入参/出参，移植保留
    implementation("com.alibaba:fastjson:1.2.83")
}
