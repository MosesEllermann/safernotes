from django.db import migrations


class Migration(migrations.Migration):
    dependencies = [
        ("tenants", "0002_initial"),
    ]

    operations = [
        migrations.RemoveField(
            model_name="organization",
            name="plan",
        ),
        migrations.RunSQL(
            sql="DROP TABLE IF EXISTS billing_billingevent;",
            reverse_sql=migrations.RunSQL.noop,
        ),
        migrations.RunSQL(
            sql="DROP TABLE IF EXISTS subscriptions_subscription;",
            reverse_sql=migrations.RunSQL.noop,
        ),
    ]
