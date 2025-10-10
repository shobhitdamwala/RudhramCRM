import Client from "../Models/Client.js";
import Lead from "../Models/Lead.js";

export const addLead = async (req, res) => {
  try {
    const {
      source,
      rawForm,
      name,
      email,
      phone,
      businessName,
      businessCategory,
      subCompanyIds,
      chosenServices,
      status,
      assignedTo,
    } = req.body;

    // Basic validation
    if (!name || !phone) {
      return res.status(400).json({
        success: false,
        message: "Name and phone number are required.",
      });
    }

    const newLead = new Lead({
      source,
      rawForm,
      name,
      email,
      phone,
      businessName,
      businessCategory,
      subCompanyIds,
      chosenServices,
      status,
      assignedTo,
    });

    const savedLead = await newLead.save();

    res.status(201).json({
      success: true,
      message: "Lead added successfully.",
      data: savedLead,
    });
  } catch (error) {
    console.error("Error adding lead:", error);
    res.status(500).json({
      success: false,
      message: "Server error while adding lead.",
      error: error.message,
    });
  }
};

export const getAllLeads = async (req, res) => {
  try {
    const leads = await Lead.find()
      .populate("assignedTo", "fullName email")
      .populate("subCompanyIds", "name");

    res.status(200).json({
      success: true,
      count: leads.length,
      data: leads,
    });
  } catch (error) {
    console.error("Error fetching leads:", error);
    res.status(500).json({
      success: false,
      message: "Server error while fetching leads.",
      error: error.message,
    });
  }
};

export const getLeadById = async (req, res) => {
  try {
    const { id } = req.params;

    const lead = await Lead.findById(id)
      .populate("assignedTo", "fullName email")
      .populate("subCompanyIds", "name");

    if (!lead) {
      return res.status(404).json({
        success: false,
        message: "Lead not found.",
      });
    }
    res.status(200).json({
      success: true,
      data: lead,
    });
  } catch (error) {
    console.error("Error fetching lead by ID:", error);
    res.status(500).json({
      success: false,
      message: "Server error while fetching lead.",
      error: error.message,
    });
  }
};


export const deleteLead = async (req, res) => {
  try {
    const { id } = req.params;

    const deletedLead = await Lead.findByIdAndDelete(id);

    if (!deletedLead) {
      return res.status(404).json({
        success: false,
        message: "Lead not found or already deleted.",
      });
    }

    res.status(200).json({
      success: true,
      message: "Lead deleted successfully.",
      data: deletedLead,
    });
  } catch (error) {
    console.error("Error deleting lead:", error);
    res.status(500).json({
      success: false,
      message: "Server error while deleting lead.",
      error: error.message,
    });
  }
};

export const convertLeadToClient = async (req, res) => {
  try {
    const { leadId } = req.params;
    const userId = req.user?._id; // assuming authentication middleware adds user

    // 1️⃣ Find the lead
    const lead = await Lead.findById(leadId);
    if (!lead) {
      return res.status(404).json({ success: false, message: "Lead not found" });
    }

    // 2️⃣ Check if already converted
    const existingClient = await Client.findOne({ leadId: lead._id });
    if (existingClient) {
      return res.status(400).json({
        success: false,
        message: "Lead has already been converted to a client.",
      });
    }
    // 3️⃣ Create new client using lead data
    const newClient = new Client({
      leadId: lead._id,
      name: lead.name,
      email: lead.email,
      phone: lead.phone,
      businessName: lead.businessName,
      meta: {
        source: lead.source,
        businessCategory: lead.businessCategory,
        chosenServices: lead.chosenServices,
      },
      createdBy: userId,
    });

    await newClient.save();

    // 4️⃣ Update lead status to "converted"
    lead.status = "converted";
    await lead.save();

    res.status(201).json({
      success: true,
      message: "Lead successfully converted to client.",
      client: newClient,
    });
  } catch (error) {
    console.error("Error converting lead:", error);
    res.status(500).json({
      success: false,
      message: "Server error while converting lead.",
      error: error.message,
    });
  }
};