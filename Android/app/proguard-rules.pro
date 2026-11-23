# Regler för R8 i release-bygget. Biblioteken har egna regler i sina jar- och aar-filer (kotlinx.serialization, Ktor,
# OkHttp, WorkManager och Glance). Reglerna här är de som appen själv behöver, utöver dem. Ett röktest av release-bygget
# i emulatorn görs efter varje ändring här, se docs/specs/2026-11-23-android-enhetschecklista.md.

# Radnummer i kraschrapporter. Mapping-filen sparas med varje bygge i releasejobbet.
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile

# kotlinx.serialization: klasser med @Serializable behåller sina genererade serialiserare, utöver bibliotekets egna
# regler. Navigationens nycklar sparas när appen dödas och slås upp med serializer() i Companion, eller INSTANCE för
# data object.
-keepattributes RuntimeVisibleAnnotations,AnnotationDefault,InnerClasses,Signature
-if @kotlinx.serialization.Serializable class se.hardyson.sophamtning.**
-keepclassmembers class se.hardyson.sophamtning.<1> {
    static se.hardyson.sophamtning.<1>$Companion Companion;
    public static se.hardyson.sophamtning.<1> INSTANCE;
}
-if @kotlinx.serialization.Serializable class se.hardyson.sophamtning.**
-keepclassmembers class se.hardyson.sophamtning.<1>$Companion {
    kotlinx.serialization.KSerializer serializer(...);
}

# Glance skapar knappens ActionCallback från klassnamnet.
-keep class * implements androidx.glance.appwidget.action.ActionCallback {
    <init>();
}
