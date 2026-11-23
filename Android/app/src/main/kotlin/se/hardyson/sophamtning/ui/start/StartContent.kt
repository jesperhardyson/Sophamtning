package se.hardyson.sophamtning.ui.start

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import se.hardyson.sophamtning.ui.components.AppSymbols
import se.hardyson.sophamtning.ui.components.Chevron
import se.hardyson.sophamtning.ui.theme.ThemeToken
import se.hardyson.sophamtning.ui.theme.Weight
import se.hardyson.sophamtning.ui.theme.brandText
import se.hardyson.sophamtning.ui.theme.color
import se.hardyson.sophamtning.ui.theme.uiText

/**
 * Startvyn utan sparade adresser, som det tomma läget i HomeView.swift: frågan, fältet som öppnar adressökningen och
 * kommunfrågan. Kärlet med pratbubblorna och introt kommer i plan 4b. Introt med logotypen ersätts av systemets startskärm.
 */
@Composable
fun StartContent(onSearch: () -> Unit, onKommun: () -> Unit) {
    Column {
        Text("När töms dina kärl?", style = brandText(34), color = ThemeToken.Text.color, modifier = Modifier.padding(top = 16.dp).semantics { heading() })
        Text(
            "Skriv in din adress så ser du vilka kärl som töms och när. Inget konto behövs.",
            style = uiText(18, Weight.SEMIBOLD),
            color = ThemeToken.Text2.color,
            modifier = Modifier.padding(top = 14.dp),
        )
        // Fältet öppnar adressökningen.
        Row(
            Modifier
                .padding(top = 24.dp)
                .fillMaxWidth()
                .heightIn(min = 48.dp)
                .background(ThemeToken.Surface.color, CircleShape)
                .border(1.dp, ThemeToken.Border.color, CircleShape)
                .clickable(role = Role.Button, onClick = onSearch)
                .padding(horizontal = 18.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Icon(Icons.Filled.Search, contentDescription = null, tint = ThemeToken.Text2.color)
            Text("Gata och husnummer", style = uiText(18, Weight.SEMIBOLD), color = ThemeToken.Text2.color)
        }
        Row(Modifier.padding(top = 16.dp).semantics(mergeDescendants = true) {}, horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Outlined.CheckCircle, contentDescription = null, tint = ThemeToken.BrandText.color, modifier = Modifier.size(20.dp))
            Text("Adressen sparas bara i din telefon.", style = uiText(15, Weight.BOLD), color = ThemeToken.BrandText.color)
        }
        val shape = RoundedCornerShape(20.dp)
        Row(
            Modifier
                .padding(top = 20.dp)
                .fillMaxWidth()
                .background(ThemeToken.Surface.color, shape)
                .border(1.dp, ThemeToken.Border.color, shape)
                .clickable(role = Role.Button, onClick = onKommun)
                .padding(14.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Box(Modifier.size(44.dp).background(ThemeToken.BrandSoft.color, RoundedCornerShape(14.dp)), contentAlignment = Alignment.Center) {
                Icon(AppSymbols.Map, contentDescription = null, tint = ThemeToken.BrandText.color)
            }
            Text("Finns min kommuns hämtningsschema?", style = uiText(18, Weight.HEAVY), color = ThemeToken.Text.color, modifier = Modifier.weight(1f))
            Chevron()
        }
    }
}
