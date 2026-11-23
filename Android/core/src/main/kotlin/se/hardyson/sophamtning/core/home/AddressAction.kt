package se.hardyson.sophamtning.core.home

/** Valen för en adress i menyn och bland TalkBacks åtgärder, i samma ordning som i adressvyn. */
enum class AddressAction {
    Rename, MakePrimary, Notifications, LiveActivity, Remove;

    companion object {
        /** Gör till huvudadress finns bara för de andra adresserna, och Live Update bara för huvudadressen. */
        fun choices(isPrimary: Boolean): List<AddressAction> = buildList {
            add(Rename)
            if (!isPrimary) add(MakePrimary)
            add(Notifications)
            if (isPrimary) add(LiveActivity)
            add(Remove)
        }
    }
}
