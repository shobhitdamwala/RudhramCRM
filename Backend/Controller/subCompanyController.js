import SubCompany from "../Models/SubCompany.js";

export const createSubCompany  = async (req, res) => {
    try {
    const { name, description, logoUrl, invoiceFormat, receiptFormat, services } = req.body;

    if (!name ) {
      return res.status(400).json({ success: false, message: "Name are required" });
    }

    const existing = await SubCompany.findOne({ name });
    if (existing) {
      return res.status(400).json({ success: false, message: "SubCompany already exists" });
    }

    const subCompany = new SubCompany({
      name,
      description,
      logoUrl,
      invoiceFormat,
      receiptFormat,
      services
    });

    await subCompany.save();

    res.status(201).json({
      success: true,
      message: "SubCompany created successfully",
      data: subCompany
    });
  } catch (error) {
    console.error("Error creating SubCompany:", error);
    res.status(500).json({ success: false, message: "Server Error", error: error.message });
  }
}

export const getAllSubCompanies = async (req, res) => {
  try {
    const subCompanies = await SubCompany.find();

    if (!subCompanies || subCompanies.length === 0) {
      return res.status(404).json({
        success: false,
        message: "No sub-companies found",
      });
    }

    res.status(200).json({
      success: true,
      count: subCompanies.length,
      data: subCompanies,
    });
  } catch (error) {
    console.error("Error fetching SubCompanies:", error);
    res.status(500).json({
      success: false,
      message: "Server Error",
      error: error.message,
    });
  }
};

// ✅ GET sub-company by ID
export const getSubCompanyById = async (req, res) => {
  try {
    const { id } = req.params;

    // Validate ID format
    if (!id || !id.match(/^[0-9a-fA-F]{24}$/)) {
      return res.status(400).json({
        success: false,
        message: "Invalid SubCompany ID format",
      });
    }

    const subCompany = await SubCompany.findById(id);

    if (!subCompany) {
      return res.status(404).json({
        success: false,
        message: "SubCompany not found",
      });
    }

    res.status(200).json({
      success: true,
      data: subCompany,
    });
  } catch (error) {
    console.error("Error fetching SubCompany by ID:", error);
    res.status(500).json({
      success: false,
      message: "Server Error",
      error: error.message,
    });
  }
};