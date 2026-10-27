// Sim addition for the siege fx/training port (no rule changes): what tutorial.gd / training.gd / spell_fx.gd reach in the
// sim that the port keeps private. GDScript has no privacy -- the tutorial and the training call moba.gd's _spawn_camp,
// _bot_learn, _bot_shop, _fight_h, _enemy_tower_near, _hit_structure, _hit_point and _bot_ult directly (Kael and the
// training's foes are driven with the bots' own moves) -- so these forward to the private ports under the names the
// guide's rule gives (_spawn_camp -> _SpawnCamp). Unit.Duplicate() is GDScript's u.duplicate() of a unit's dictionary
// (shallow, as Dictionary.duplicate(): the lists inside are shared), for spell_fx.gd's warm-up (_warm_states).
namespace Fatebound.Sim
{
    public sealed partial class Moba
    {
        public void _SpawnCamp(Camp camp) => SpawnCamp(camp);
        public void _BotLearn(Unit u) => BotLearn(u);
        public void _BotShop(Unit u) => BotShop(u);
        public void _FightH(Unit u, Unit foe) => FightH(u, foe);
        public Tower _EnemyTowerNear(Unit u, double r) => EnemyTowerNear(u, r);
        public void _HitStructure(Unit u, Tower tw) => HitStructure(u, tw);
        public void _HitPoint(Unit u, Vec2 p, double r, double within = double.PositiveInfinity) => HitPoint(u, p, r, within);
        public bool _BotUlt(Unit u) => BotUlt(u);
    }

    public sealed partial class Unit
    {
        /// <summary>u.duplicate(): a shallow copy (the fields' lists and records shared, as a Dictionary's duplicate()).</summary>
        public Unit Duplicate()
        {
            var u = (Unit)MemberwiseClone();
            if (extra != null) u.extra = new System.Collections.Generic.Dictionary<string, object>(extra);   // (its own keys, as the copy's)
            return u;
        }
    }
}
