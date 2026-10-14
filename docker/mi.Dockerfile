# Custom WSO2 Micro Integrator image with the H2 JDBC driver added to the
# server classpath, so the JamiiSavingsDataSource (jdbc:h2:file:...) resolves
# at runtime. Pinned to the exact MI version used throughout this project.
FROM wso2/wso2mi:4.6.0

# JDBC driver jars go directly under <CARBON_HOME>/lib for MI 4.x.
COPY --chown=wso2carbon:wso2 drivers/h2-2.2.224.jar /home/wso2carbon/wso2mi-4.6.0/lib/h2-2.2.224.jar

# Pre-create the H2 data directory with correct ownership. When an empty named
# volume is first mounted over an existing image directory, Docker copies that
# directory's contents/permissions into the volume - this avoids the H2
# database files being created as root and the MI process (uid wso2carbon)
# being denied write access.
USER root
RUN mkdir -p /home/wso2carbon/wso2mi-4.6.0/dbdata && \
    chown -R wso2carbon:wso2 /home/wso2carbon/wso2mi-4.6.0/dbdata
USER wso2carbon
