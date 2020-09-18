# Builds a Libpng framework for the iPhone and the iPhone Simulator.
# Creates a set of universal libraries that can be used on an iPhone and in the
# iPhone simulator. Then creates a pseudo-framework to make using libpng in Xcode
# less painful.
#
# To configure the script, define:
#    IPHONE_SDKVERSION: iPhone SDK version (e.g. 8.1)
#
# Then go get the source tar.bz of the libpng you want to build, shove it in the
# same directory as this script, and run "./libpng.sh". Grab a cuppa. And voila.
#===============================================================================

: ${LIB_VERSION:=1.6.37}
: ${LIB_SHORTVERSION:=16} # todo: extract from LIB_VERSION

# Current iPhone SDK
: ${IPHONE_SDKVERSION:=`xcodebuild -showsdks | grep iphoneos | egrep "[[:digit:]]+\.[[:digit:]]+" -o | tail -1`}
# Specific iPhone SDK
# : ${IPHONE_SDKVERSION:=8.1}

: ${XCODE_ROOT:=`xcode-select -print-path`}

: ${TARBALLDIR:=`pwd`}
: ${SRCDIR:=`pwd`/src}
: ${IOSBUILDDIR:=`pwd`/ios/build}
: ${OSXBUILDDIR:=`pwd`/osx/build}
: ${PREFIXDIR:=`pwd`/ios/prefix}
: ${IOSFRAMEWORKDIR:=`pwd`/ios/framework}
: ${OSXFRAMEWORKDIR:=`pwd`/osx/framework}

LIB_TARBALL=$TARBALLDIR/libpng-$LIB_VERSION.tar.gz
LIB_SRC=$SRCDIR/libpng-${LIB_VERSION}

#===============================================================================
ARM_DEV_CMD="xcrun --sdk iphoneos"
SIM_DEV_CMD="xcrun --sdk iphonesimulator"

#===============================================================================
# Functions
#===============================================================================

abort()
{
    echo
    echo "Aborted: $@"
    exit 1
}

doneSection()
{
    echo
    echo "================================================================="
    echo "Done"
    echo
}

#===============================================================================

cleanEverythingReadyToStart()
{
    echo Cleaning everything before we start to build...

    rm -rf iphone-build iphonesim-build
    rm -rf $IOSBUILDDIR
    rm -rf $PREFIXDIR
    rm -rf $IOSFRAMEWORKDIR/$FRAMEWORK_NAME.framework

    doneSection
}

#===============================================================================

downloadLibpng()
{
    if [ ! -s $LIB_TARBALL ]; then
        echo "Downloading libpng ${LIB_VERSION}"
        curl -L -o $LIB_TARBALL http://sourceforge.net/projects/libpng/files/libpng$LIB_SHORTVERSION/${LIB_VERSION}/libpng-${LIB_VERSION}.tar.gz
    fi

    doneSection
}

#===============================================================================

unpackLibpng()
{
    [ -f "$LIB_TARBALL" ] || abort "Source tarball missing."

    echo Unpacking libpng into $SRCDIR...

    [ -d $SRCDIR ]    || mkdir -p $SRCDIR
    [ -d $LIB_SRC ] || ( cd $SRCDIR; tar xfj $LIB_TARBALL )
    [ -d $LIB_SRC ] && echo "    ...unpacked as $LIB_SRC"

    doneSection
}

#===============================================================================

buildLibpngForIPhoneOS()
{
    MIN_IOS_VERSION="10.0" # explicitly accept 32 bit build

	export CC="${XCODE_ROOT}/usr/bin/gcc"
	export CXX="${XCODE_ROOT}/usr/bin/g++" 
    
    # avoid the `LDFLAGS` env to include the homebrew Cellar
    export LDFLAGS=""
    
    cd $LIB_SRC

    echo Building Libpng for iPhoneSimulator
    PLATFORM=iPhoneSimulator
    ARCHS="-arch i386 -arch x86_64"
    EXTRA_COMPILER_FLAGS=""
    SYSROOT=$XCODE_ROOT/Platforms/$PLATFORM.platform/Developer/SDKs/${PLATFORM}${IPHONE_SDKVERSION}.sdk
    echo "isysroot is $SYSROOT"
    HOST="i386-apple-darwin11" # probably exact value is not used, needed to avoid configure script wanting to run the built executable
    export CFLAGS="-O3 $ARCHS -isysroot $SYSROOT -mios-simulator-version-min=${MIN_IOS_VERSION} -Wno-error-implicit-function-declaration $EXTRA_COMPILER_FLAGS"
    make distclean
    ./configure --host=$HOST --prefix=$PREFIXDIR/iphonesim-build --disable-dependency-tracking --enable-static=yes --enable-shared=no
    make
    make install
    doneSection

    echo Building Libpng for iPhone
    PLATFORM=iPhoneOS
    ARCHS="-arch armv7 -arch armv7s -arch arm64"
    EXTRA_COMPILER_FLAGS="-fembed-bitcode"
    SYSROOT=$XCODE_ROOT/Platforms/$PLATFORM.platform/Developer/SDKs/${PLATFORM}${IPHONE_SDKVERSION}.sdk
    echo "isysroot is $SYSROOT"
    HOST="arm-apple-darwin64"
	export CFLAGS="-O3 $ARCHS -isysroot $SYSROOT -mios-version-min=${MIN_IOS_VERSION} $EXTRA_COMPILER_FLAGS"
    make distclean
    ./configure --host=$HOST --prefix=$PREFIXDIR/iphone-build --disable-dependency-tracking --enable-static=yes --enable-shared=no
    make
    make install
    doneSection
}

#===============================================================================

scrunchAllLibsTogetherInOneLibPerPlatform()
{
    cd $PREFIXDIR

    # iOS Device
    mkdir -p $IOSBUILDDIR/armv7
    mkdir -p $IOSBUILDDIR/armv7s
    mkdir -p $IOSBUILDDIR/arm64

    # iOS Simulator
    mkdir -p $IOSBUILDDIR/i386
    mkdir -p $IOSBUILDDIR/x86_64

    ALL_LIBS=""

    echo Splitting all existing fat binaries...

    $ARM_DEV_CMD lipo "iphone-build/lib/libpng.a" -thin armv7 -o $IOSBUILDDIR/armv7/libpng.a
    $ARM_DEV_CMD lipo "iphone-build/lib/libpng.a" -thin armv7s -o $IOSBUILDDIR/armv7s/libpng.a
    $ARM_DEV_CMD lipo "iphone-build/lib/libpng.a" -thin arm64 -o $IOSBUILDDIR/arm64/libpng.a

    $SIM_DEV_CMD lipo "iphonesim-build/lib/libpng.a" -thin i386 -o $IOSBUILDDIR/i386/libpng.a
    $SIM_DEV_CMD lipo "iphonesim-build/lib/libpng.a" -thin x86_64 -o $IOSBUILDDIR/x86_64/libpng.a

    echo Build an universal library
}

#===============================================================================
buildFramework()
{
    : ${1:?}
    FRAMEWORKDIR=$1
    BUILDDIR=$2

    VERSION_TYPE=Alpha
    FRAMEWORK_NAME=libpng
    FRAMEWORK_VERSION=A

    FRAMEWORK_CURRENT_VERSION=$LIB_VERSION
    FRAMEWORK_COMPATIBILITY_VERSION=$LIB_VERSION

    FRAMEWORK_BUNDLE=$FRAMEWORKDIR/$FRAMEWORK_NAME.framework
    echo "Framework: Building $FRAMEWORK_BUNDLE from $BUILDDIR..."

    rm -rf $FRAMEWORK_BUNDLE

    echo "Framework: Setting up directories..."
    mkdir -p $FRAMEWORK_BUNDLE
    mkdir -p $FRAMEWORK_BUNDLE/Versions
    mkdir -p $FRAMEWORK_BUNDLE/Versions/$FRAMEWORK_VERSION
    mkdir -p $FRAMEWORK_BUNDLE/Versions/$FRAMEWORK_VERSION/Resources
    mkdir -p $FRAMEWORK_BUNDLE/Versions/$FRAMEWORK_VERSION/Headers
    mkdir -p $FRAMEWORK_BUNDLE/Versions/$FRAMEWORK_VERSION/Documentation

    echo "Framework: Creating symlinks..."
    ln -s $FRAMEWORK_VERSION               $FRAMEWORK_BUNDLE/Versions/Current
    ln -s Versions/Current/Headers         $FRAMEWORK_BUNDLE/Headers
    ln -s Versions/Current/Resources       $FRAMEWORK_BUNDLE/Resources
    ln -s Versions/Current/Documentation   $FRAMEWORK_BUNDLE/Documentation
    ln -s Versions/Current/$FRAMEWORK_NAME $FRAMEWORK_BUNDLE/$FRAMEWORK_NAME

    FRAMEWORK_INSTALL_NAME=$FRAMEWORK_BUNDLE/Versions/$FRAMEWORK_VERSION/$FRAMEWORK_NAME

    echo "Lipoing library into $FRAMEWORK_INSTALL_NAME..."
    $ARM_DEV_CMD lipo -create $BUILDDIR/*/libpng.a -o "$FRAMEWORK_INSTALL_NAME" || abort "Lipo $1 failed"

    echo "Framework: Copying includes..."
    cp -r $PREFIXDIR/iphone-build/include/*  $FRAMEWORK_BUNDLE/Headers/

    echo "Framework: Creating plist..."
    cat > $FRAMEWORK_BUNDLE/Resources/Info.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
<key>CFBundleDevelopmentRegion</key>
<string>English</string>
<key>CFBundleExecutable</key>
<string>${FRAMEWORK_NAME}</string>
<key>CFBundleIdentifier</key>
<string>org.libpng</string>
<key>CFBundleInfoDictionaryVersion</key>
<string>6.0</string>
<key>CFBundlePackageType</key>
<string>FMWK</string>
<key>CFBundleSignature</key>
<string>????</string>
<key>CFBundleVersion</key>
<string>${FRAMEWORK_CURRENT_VERSION}</string>
</dict>
</plist>
EOF

    doneSection
}

#===============================================================================
# Execution starts here
#===============================================================================

mkdir -p $IOSBUILDDIR

# cleanEverythingReadyToStart #may want to comment if repeatedly running during dev

echo "LIB_VERSION:       $LIB_VERSION"
echo "LIB_SRC:           $LIB_SRC"
echo "IOSBUILDDIR:       $IOSBUILDDIR"
echo "PREFIXDIR:         $PREFIXDIR"
echo "IOSFRAMEWORKDIR:   $IOSFRAMEWORKDIR"
echo "IPHONE_SDKVERSION: $IPHONE_SDKVERSION"
echo "XCODE_ROOT:        $XCODE_ROOT"
echo

downloadLibpng
unpackLibpng
buildLibpngForIPhoneOS
scrunchAllLibsTogetherInOneLibPerPlatform
buildFramework $IOSFRAMEWORKDIR $IOSBUILDDIR

echo "Completed successfully"

#===============================================================================
