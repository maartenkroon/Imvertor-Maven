<?xml version="1.0" encoding="UTF-8"?>
<!-- 
 * Copyright (C) 2016 Dienst voor het kadaster en de openbare registers
 * 
 * This file is part of Imvertor.
 *
 * Imvertor is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * Imvertor is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with Imvertor.  If not, see <http://www.gnu.org/licenses/>.
-->
<xsl:stylesheet 
    xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
    xmlns:xs="http://www.w3.org/2001/XMLSchema" 
    
    xmlns:imvert="http://www.imvertor.org/schema/system"
    xmlns:ext="http://www.imvertor.org/xsl/extensions"
    xmlns:imf="http://www.imvertor.org/xsl/functions"
    
    exclude-result-prefixes="#all"
    version="2.0">
    
    <!-- 
        Check if any reference occurs to <<Intern>>. 
        In that case, get the referenced imvertor XML and copy to this invert XML.
        This effectively inserts/imports info the model.
        
        Implements REDMINE #487612
    -->
    
    <xsl:import href="../common/Imvert-common.xsl"/>
    
    <xsl:variable name="managed-output-folder" select="imf:get-config-string('system','managedoutputfolder')"/>
    
    <xsl:variable name="intern-packs" select="//imvert:package[imvert:stereotype = imf:get-config-stereotypes('stereotype-name-internal-package')]" as="element(imvert:package)*"/>
    <xsl:variable name="intern-referenced-packages" select="for $d in $intern-packs return imf:get-intern-doc($d)/imvert:packages/imvert:package" as="element(imvert:package)*"/>
    <xsl:variable name="locally-defined-packages" select="/imvert:packages/imvert:package" as="element(imvert:package)*"/>
    
    <!-- get the classes that are external, i.e. may be referenced by the internal package. Must be located in a domain package. -->
    <xsl:variable name="intern-classes" select="$intern-referenced-packages[imvert:stereotype=imf:get-config-stereotypes('stereotype-name-domain-package')]/imvert:class" as="element(imvert:class)*"/>
    
    <xsl:template match="/imvert:packages">
        <xsl:copy>
            <xsl:sequence select="imf:compile-imvert-header(.)"/>
            <xsl:choose>
                <xsl:when test="exists($intern-packs)">
                    <!-- process all but reset the type IDs for interfaces to an internal package -->
                    <xsl:apply-templates select="imvert:package" mode="intern-redirect"/>
                    <!-- now add the internal packages -->
                    <xsl:apply-templates select="$intern-referenced-packages" mode="intern-origin"/>         
                </xsl:when>
                <xsl:otherwise>
                    <!-- not part of the metamodel of no intern packjages defined. -->
                    <xsl:sequence select="imvert:package"/>
                </xsl:otherwise>
            </xsl:choose>
        </xsl:copy>
    </xsl:template>
    
    <xsl:template match="imvert:package[imvert:id = $intern-packs/imvert:id]" mode="intern-redirect">
        <xsl:comment>Internal removed: <xsl:value-of select="imvert:name"/></xsl:comment>
    </xsl:template>
    
    <xsl:template match="imvert:type-id" mode="intern-redirect">
        <xsl:variable name="id" select="."/>
        <xsl:variable name="interface" select="imf:get-construct-by-id($id,$intern-classes)"/>
        <xsl:variable name="interface-name" select="$interface/imvert:name"/>
        <xsl:variable name="interface-package-name" select="$interface/../imvert:name"/>
        <xsl:variable name="referenced-construct" select="$intern-classes[imvert:name=$interface-name]"/>
        <xsl:choose>
            <xsl:when test="empty($interface)">
                <xsl:copy-of select="."/>
            </xsl:when>
            <xsl:when test="empty($referenced-construct)">
                <xsl:sequence select="imf:msg(..,'ERROR','Interface cannot be resolved to a valid construct: [1]',(../imvert:type-name))"/>
            </xsl:when>
            <xsl:otherwise>
                <!-- pass a new ID -->
                <imvert:type-id original="{$id}">
                    <xsl:value-of select="$referenced-construct/imvert:id"/>
                </imvert:type-id>
            </xsl:otherwise>
        </xsl:choose>   
    </xsl:template>
    
    <!-- add this package, but only when not already inserted by the calling model -->
    <xsl:template match="imvert:package" mode="intern-origin">
        <xsl:choose>
            <xsl:when test="imvert:id = $locally-defined-packages/imvert:id">
                <!-- skip; already included -->
            </xsl:when>
            <xsl:otherwise>
                <xsl:copy>
                    <xsl:attribute name="origin">system</xsl:attribute>
                    <xsl:apply-templates mode="#current"/>
                </xsl:copy>
            </xsl:otherwise>
        </xsl:choose>
    </xsl:template>
   
    <xsl:template match="node()" mode="intern-origin intern-redirect">
        <xsl:copy>
            <xsl:copy-of select="@*"/>
            <xsl:apply-templates mode="#current"/>
        </xsl:copy>
    </xsl:template>

    <xsl:function name="imf:get-intern-doc" as="document-node()?">
        <xsl:param name="intern-pack"/>
        <xsl:variable name="project" select="imf:get-tagged-value($intern-pack,'InternalProject')"/>
        <xsl:variable name="application" select="imf:get-tagged-value($intern-pack,'InternalName')"/>
        <xsl:variable name="release" select="imf:get-tagged-value($intern-pack,'InternalRelease')"/>
        <xsl:variable name="subpath" select="concat('applications\',$project,'\',$application,'\',$release)"/>
        <xsl:variable name="path" select="concat($managed-output-folder, '\',$subpath,'\etc\system.imvert.xml')"/>
        <xsl:variable name="doc" select="imf:document($path)"/>
        <xsl:sequence select="imf:msg($intern-pack,'DEBUG','Internal path resolves to [1]', $path)"/>
        <xsl:choose>
            <xsl:when test="empty($doc)">
                <xsl:sequence select="imf:msg($intern-pack,'ERROR','No model found for internal package, tried: [1]',($subpath))"/>
            </xsl:when>
            <xsl:otherwise>
                <xsl:sequence select="$doc"/>
            </xsl:otherwise>
        </xsl:choose>
    </xsl:function>
    
    <xsl:function name="imf:get-tagged-value" as="xs:string?">
        <xsl:param name="this" as="node()"/>
        <xsl:param name="tv-name" as="xs:string"/>
        <xsl:variable name="norm-name" select="imf:get-config-item-by-id($configuration-tvset-file,$tv-name)/name[@lang=$language]"/>
        <xsl:variable name="tv" select="$this/imvert:tagged-values/imvert:tagged-value[imvert:name = $norm-name]"/>
        <xsl:value-of select="string($tv/imvert:value)"/>
    </xsl:function>
    
    <xsl:function name="imf:get-config-item-by-id">
        <xsl:param name="config-tree"/>
        <xsl:param name="id"/>
        <xsl:sequence select="($config-tree//*[@id=$id])[last()]"/>
    </xsl:function>
    
</xsl:stylesheet>
